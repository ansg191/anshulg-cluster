#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';

use Getopt::Long qw(GetOptions);
use Data::Dumper qw(Dumper);
use Pod::Usage   qw(&pod2usage);
use File::Find   qw(find);
use English      qw(-no_match_vars);
use File::pushd;
use Readonly;

our $VERSION = 0.01;
Readonly my $DEFAULT_PORT => 80;

# Check if the provided cluster is valid
sub check_cluster {
    my ($cluster) = @_;

    # Check if the cluster folder exists
    die "Cluster folder not found: $cluster\n" if ( !-d $cluster );

    # Check if the apps folder exists
    die "Apps folder not found: $cluster/apps\n" if ( !-d "$cluster/apps" );

    return 0;
}

# Gets the top level domain of the cluster
sub get_tld {
    my ($cluster) = @_;

    # Check if the cluster folder exists
    check_cluster $cluster;

    # Open the cluster's values.yaml file
    open my $fh, '<', "$cluster/apps/values.yaml"
      or croak("Could not open file: $OS_ERROR");

    # Read the file line by line
    while ( my $line = <$fh> ) {

        # If the line contains the tld key, return the value
        if ( $line =~ /^tld:\s*(.*)/sxm ) {
            close $fh or carp("Failed to close file: $OS_ERROR");
            return $1;
        }
    }

    close $fh or carp("Failed to close file: $OS_ERROR");
    die "tld key not found in $cluster/apps/values.yaml\n";
}

sub create_app_file {
    my ( $cluster, $name ) = @_;

    # Copy yaml template to the application file
    my $app_yaml = <<"END_YAML";
apiVersion: v1
kind: Namespace
metadata:
  name: $name
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $name
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    server: {{ .Values.spec.destination.server }}
    namespace: $name
  project: default
  source:
    repoURL: {{ .Values.spec.source.repoURL }}
    targetRevision: {{ .Values.spec.source.branch }}
    path: $cluster/$name
END_YAML

    # Create the application file
    open my $fh, '>', "$cluster/apps/templates/$name.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $app_yaml or croak($OS_ERROR);
    close $fh             or carp("Failed to close file: $OS_ERROR");

    system "git add $cluster/apps/templates/$name.yaml";
    return;
}

sub command_new {
    my $name;
    my $cluster;
    my $port     = $DEFAULT_PORT;
    my $stateful = 0;
    my $help     = 0;
    GetOptions(
        'name=s'    => \$name,
        'cluster=s' => \$cluster,
        'port=i'    => \$port,
        'stateful'  => \$stateful,
        'help|?'    => \$help,
    ) or pod2usage(2);
    if ( $help != 0 ) {
        pod2usage( -verbose => 2 );
    }

    die "Missing required option: --name\n"    if ( !defined $name );
    die "Missing required option: --cluster\n" if ( !defined $cluster );

    check_cluster $cluster;

    print "Creating new application: `$name` in cluster: `$cluster`\n";

    # Get the TLD of the cluster
    my $tld = get_tld $cluster;

    # Create the application folder
    mkdir "$cluster/$name";

    # Create the application file
    create_app_file $cluster, $name;

    # Give the port a name
    my $port_name = 'http';

    # Create service YAML
    my $service_yaml = <<"END_YAML";
apiVersion: v1
kind: Service
metadata:
  name: $name
spec:
  selector:
    app: $name
  ports:
    - protocol: TCP
      port: 80
      targetPort: $port_name
  type: ClusterIP
END_YAML
    open my $fh, '>', "$cluster/$name/service.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $service_yaml;
    close $fh or carp("Failed to close file: $OS_ERROR");
    system "git add $cluster/$name/service.yaml";

    # Create ingress YAML
    my $sec_ns = ( $cluster eq 'k8s' ) ? 'traefik' : 'kube-system';
    my $extra_match =
      ( $cluster eq 'rpi5' ) ? "|| Host(`$name.internal`)" : q{};
    my $ingress_yaml = <<"END_YAML";
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: $name
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`$name.$tld`) $extra_match
      middlewares:
        - name: security-headers
          namespace: $sec_ns
      services:
        - name: $name
          port: 80
  tls:
    secretName: $name-cert-tls
    domains:
      - main: $name.$tld
END_YAML
    open $fh, '>', "$cluster/$name/ingress.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $ingress_yaml;
    close $fh or carp("Failed to close file: $OS_ERROR");
    system "git add $cluster/$name/ingress.yaml";

    # Create certificate YAML
    my $certificate_yaml = <<"END_YAML";
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $name-cert
spec:
  secretName: $name-cert-tls
  commonName: $name.$tld
  dnsNames:
    - $name.$tld
  duration: 2160h0m0s
  renewBefore: 720h0m0s
  privateKey:
    algorithm: ECDSA
    size: 384
    rotationPolicy: Always
  subject:
    organizations:
      - Anshul Gupta
    organizationalUnits:
      - $cluster
    provinces:
      - California
    countries:
      - US
  issuerRef:
    group: cas-issuer.jetstack.io
    kind: GoogleCASClusterIssuer
    name: anshulg-ca
END_YAML
    open $fh, '>', "$cluster/$name/certificate.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $certificate_yaml;
    close $fh or carp("Failed to close file: $OS_ERROR");
    system "git add $cluster/$name/certificate.yaml";

# Create deployment YAML if stateful is not set or statefulset YAML if stateful is set
    if ( $stateful == 0 ) {
        my $deployment_yaml = <<"END_YAML";
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  labels:
    app: $name
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $name
  template:
    metadata:
      name: $name
      labels:
        app: $name
    spec:
      containers:
        - name: $name
          image: IMAGE
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: $port
              protocol: TCP
              name: $port_name
          env: []
          #resources:
          #  requests:
          #    cpu: 250m
          #    memory: 500Mi
          #  limits:
          #    memory: 1Gi
          #livenessProbe:
          #  httpGet:
          #    port: $port_name
          #    path: /ping
          #  initialDelaySeconds: 30
          #  periodSeconds: 30
          #  timeoutSeconds: 5
          #  failureThreshold: 3
          #readinessProbe:
          #  httpGet:
          #    port: $port_name
          #    path: /ping
          #  periodSeconds: 10
          #  timeoutSeconds: 5
          #  failureThreshold: 3
      restartPolicy: Always
END_YAML
        open my $fh, '>', "$cluster/$name/deployment.yaml"
          or croak("Could not create file: $OS_ERROR");
        print {$fh} $deployment_yaml;
        close $fh or carp("Failed to close file: $OS_ERROR");
        system "git add $cluster/$name/deployment.yaml";
    }
    else {
        my $statefulset_yaml = <<"END_YAML";
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: $name
  labels:
    app: $name
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $name
  serviceName: $name
  template:
    metadata:
      name: $name
      labels:
        app: $name
    spec:
      containers:
        - name: $name
          image: IMAGE
          imagePullPolicy: IfNotPresent
          env: []
          ports:
            - containerPort: $port
              protocol: TCP
          volumeMounts:
            - mountPath: PATH
              name: data
          #resources:
          #  requests:
          #    cpu: 250m
          #    memory: 500Mi
          #  limits:
          #    memory: 1Gi
          #livenessProbe:
          #  httpGet:
          #    port: $port_name
          #    path: /ping
          #  initialDelaySeconds: 30
          #  periodSeconds: 30
          #  timeoutSeconds: 5
          #  failureThreshold: 3
          #readinessProbe:
          #  httpGet:
          #    port: $port_name
          #    path: /ping
          #  periodSeconds: 10
          #  timeoutSeconds: 5
          #  failureThreshold: 3
      restartPolicy: Always
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 1Gi
END_YAML
        open my $fh, '>', "$cluster/$name/statefulset.yaml"
          or croak("Could not create file: $OS_ERROR");
        print {$fh} $statefulset_yaml;
        close $fh or carp("Failed to close file: $OS_ERROR");
        system "git add $cluster/$name/statefulset.yaml";
    }

    print "Application $name in $cluster created successfully\n";
    return;
}

sub command_helm {
    my $name;
    my $cluster;
    my $help = 0;
    GetOptions(
        'name=s'    => \$name,
        'cluster=s' => \$cluster,
        'help|?'    => \$help,
    ) or pod2usage(2);
    if ( $help != 0 ) {
        pod2usage( -verbose => 2 );
    }

    die "Missing required option: --name\n"    if ( !defined $name );
    die "Missing required option: --cluster\n" if ( !defined $cluster );

    check_cluster $cluster;
    my $tld = get_tld $cluster;

    print "Creating Helm chart for $name in $cluster\n";

    # Create the Helm chart
    {
        my $dir = pushd("$cluster");
        system("helm create $name") == 0
          or die "Failed to create Helm chart for $name in $dir\n";
        system "git add $name";
    }

    # Create the application file
    create_app_file $cluster, $name;

    # Create ingress YAML
    my $ingress_yaml = <<"END_YAML";
{{- if .Values.ingressRoute.enabled -}}
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: {{ include "$name.fullname" . }}
spec:
  {{- with .Values.ingressRoute.entryPoints }}
  entryPoints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- \$service := include "$name.fullname" . }}
  {{- range .Values.ingressRoute.hosts }}
  routes:
    - kind: Rule
      match: Host(`{{ . }}`)
      {{- with \$.Values.ingressRoute.middlewares }}
      middlewares:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      services:
        - name: {{ \$service }}
          port: {{ \$.Values.service.port }}
  {{- end }}
  {{- if .Values.ingressRoute.tls.enabled }}
  tls:
    secretName: {{ include "$name.fullname" . }}-tls
    domains:
      {{- range .Values.ingressRoute.hosts }}
      - main: {{ . }}
      {{- end }}
  {{- end }}
{{- end }}
END_YAML
    open my $fh, '>', "$cluster/$name/templates/ingress_route.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $ingress_yaml;
    close $fh or carp("Failed to close file: $OS_ERROR");
    system "git add $cluster/$name/templates/ingress_route.yaml";

    # Create certificate YAML
    my $certificate_yaml = <<"END_YAML";
{{- if and .Values.ingressRoute.enabled .Values.ingressRoute.enabled -}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ include "$name.fullname" . }}-tls
spec:
  secretName: {{ include "$name.fullname" . }}-tls
  {{- with (first .Values.ingressRoute.hosts) }}
  commonName: {{ . | quote }}
  {{- end }}
  {{- with .Values.ingressRoute.hosts }}
  dnsNames:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  duration: {{ .Values.ingressRoute.tls.duration }}
  renewBefore: {{ .Values.ingressRoute.tls.renewBefore }}
  {{- with .Values.ingressRoute.tls.privateKey }}
  privateKey:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  subject:
    organizations:
      - Anshul Gupta
    organizationalUnits:
      - $cluster
    provinces:
      - California
    countries:
      - US
  {{- with .Values.ingressRoute.tls.issuerRef }}
  issuerRef:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
END_YAML
    open $fh, '>', "$cluster/$name/templates/certificate.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $certificate_yaml;
    close $fh or carp("Failed to close file: $OS_ERROR");
    system "git add $cluster/$name/templates/certificate.yaml";

    # Append ingressRoute options to values.yaml
    my $values_yaml = <<"END_YAML";

# Traefik IngressRoute options
ingressRoute:
  enabled: true
  entryPoints:
    - websecure
  hosts:
    - $name.$tld
  middlewares:
    - name: security-headers
      namespace: traefik
  tls:
    enabled: true
    duration: 2160h0m0s
    renewBefore: 720h0m0s
    privateKey:
      algorithm: ECDSA
      size: 384
      rotationPolicy: Always
    issuerRef:
      group: cas-issuer.jetstack.io
      kind: GoogleCASClusterIssuer
      name: anshulg-ca
END_YAML
    open my $fd, '>>', "$cluster/$name/values.yaml"
      or croak("Could not open file: $OS_ERROR");
    print {$fd} $values_yaml;
    close $fd or carp("Failed to close file: $OS_ERROR");
    system "git add $cluster/$name/values.yaml";

    print "Helm chart for $name in $cluster created successfully\n";
    return;
}

sub command_secret {
    my $name = shift @ARGV or die "Missing required argument: NAME\n";

    my $cluster;
    my $app;
    my $namespace;
    GetOptions(
        'cluster=s'   => \$cluster,
        'namespace=s' => \$namespace,
        'app=s'       => \$app,
    ) or pod2usage(2);

    die "Missing required option: --cluster\n" if ( !defined $cluster );
    die "Missing required option: --app\n"     if ( !defined $app );
    if ( !defined $namespace ) {
        $namespace = $app;
    }

    check_cluster $cluster;

    # Check for app folder in cluster
    die "App folder not found: $cluster/$app\n" if ( !-d "$cluster/$app" );

    print "Creating secret for $name/$app in $cluster/$namespace\n";

    # Call kubectl to create the secret yaml
    my $yaml =
`kubectl create secret generic $name -n $namespace --dry-run=client -o yaml @ARGV`;

    # Create secret YAML
    open my $fh, '>', "$cluster/$app/$name.unencrypted.yaml"
      or croak("Could not create file: $OS_ERROR");
    print {$fh} $yaml;
    close $fh or carp("Failed to close file: $OS_ERROR");

    print "Secret $name/$app in $cluster/$namespace created successfully\n";
    return;
}

sub seal_file {
    my ( $file, $yes, $controller, $namespace ) = @_;

    # Ask for confirmation
    if ( $yes == 0 ) {
        print "Seal $file? [y/N] ";
        my $response = <>;
        chomp $response;
        return if ( $response ne 'y' );
    }

    # Remove `.unencrypted` from the file name
    my $sealed_file = $file;
    $sealed_file =~ s/[.]unencrypted//sxm;

    print "Sealing $file into $sealed_file\n";

    # Call kubeseal to seal the secret, die if the command fails
    system(
"kubeseal --controller-name=\"$controller\" --controller-namespace=\"$namespace\" -f $file -w $sealed_file"
      ) == 0
      or die "Failed to seal $file\n";
    return;
}

sub seal_precheck {
    my ($dir) = @_;

    # Extract cluster and app from directory
    my ( $cluster, $app );
    if ( $dir =~ m{^([^/]+)/([^/]+)$}sxm ) {
        ( $cluster, $app ) = ( $1, $2 );
    }
    else {
        die "Invalid directory format. Expected 'cluster/app'.\n";
    }

    # Check cluster exists
    check_cluster $cluster;

    # Check that we are in the correct context
    my %cluster_context_map = (
        'k8s'  => 'gke',
        'rpi5' => 'default',
    );
    my $current_context = `kubectl config current-context`;
    chomp $current_context;    # Remove trailing newline from command output
    if ( exists $cluster_context_map{$cluster}
        && $cluster_context_map{$cluster} ne $current_context )
    {
        die
"Cluster context mismatch: expected '$cluster_context_map{$cluster}', but found '$current_context'\n";
    }

    return;
}

sub command_seal {
    my $namespace  = 'kube-system';
    my $controller = 'sealed-secrets';
    my $skip_check = 0;
    my $yes        = 0;
    my $help       = 0;
    GetOptions(
        'namespace=s'  => \$namespace,
        'controller=s' => \$controller,
        'skip-check'   => \$skip_check,
        'yes'          => \$yes,
        'help|?'       => \$help,
    ) or pod2usage(2);
    if ( $help != 0 ) {
        pod2usage( -verbose => 2 );
    }

    my $dir = shift @ARGV or die "Missing required argument: DIR\n";

    # Run precheck if `skip-check` is false
    if ( $skip_check == 0 ) {
        seal_precheck $dir;
    }

    # Get all unencrypted secret files in the directory
    my $wanted = sub {
        if ( -f && /[.]unencrypted[.]yaml$/sxm ) {
            seal_file( $_, $yes, $controller, $namespace );
        }
    };

    find( \&{$wanted}, $dir );
    return;
}

my $subcommand    = shift @ARGV or pod2usage(2);
my %command_table = (
    'new'    => \&command_new,
    'helm'   => \&command_helm,
    'secret' => \&command_secret,
    'seal'   => \&command_seal,
);

if ( exists $command_table{$subcommand} ) {
    $command_table{$subcommand}->();
}

# If subcommand equals help, --help or -h, print the help message
elsif ($subcommand eq 'help'
    || $subcommand eq '--help'
    || $subcommand eq '-h' )
{
    pod2usage( -verbose => 2 );
}
else {
    print "Unknown subcommand: $subcommand\n";
    pod2usage;
}

__END__

=head1 NAME

./x.pl - Performs common script operations

=head1 VERSION

This documentation refers to ./x.pl version 0.1.0.

=head1 USAGE

./x.pl [subcommand] [options]

=head1 REQUIRED ARGUMENTS

Depends on subcommand. Refer to L</DESCRIPTION>.

=head1 OPTIONS

Depends on subcommand. Refer to L</DESCRIPTION>.

=head1 DESCRIPTION

B<This program> has multiple subcommands that perform common script operations.

=head2 new

./x.pl new [--name=NAME] [--cluster=CLUSTER] [--port=PORT] [--stateful]

Create a new application.

 Options:
     -n, --name=NAME        The name of the application
     -c, --cluster=CLUSTER  The cluster to deploy the application to
     -p, --port=PORT        The port to expose the application on (default: 80)
     -s, --stateful         Create a stateful application (default: false)

=head2 helm

./x.pl helm [--name=NAME] [--cluster=CLUSTER]

Create a new helm chart application.

 Options:
     -n, --name=NAME        The name of the application
     -c, --cluster=CLUSTER  The cluster to deploy the application to

=head2 secret

./x.pl secret NAME [--cluster=CLUSTER] [--app=APP] [--namespace=NAMESPACE] -- [options]

Create a new secret.

 Options:
    -c, --cluster=CLUSTER       The cluster to deploy the secret to
    -a, --app=APP               The application to deploy the secret to
    -n, --namespace=NAMESPACE   The namespace to deploy the secret to (default: APP)

=head2 seal

./x.pl seal [--namespace=NAMESPACE] [--controller=CONTROLLER] DIR

Seal all unencrypted secrets in the directory.

 Options:
    -n, --namespace=NAMESPACE   The namespace of the Sealed Secrets controller (default: kube-system)
    -c, --controller=CONTROLLER The name of the Sealed Secrets controller (default: sealed-secrets)
    -s, --skip-check            Skip kubectl context check
    -y, --yes                   Skip confirmation

=head1 DIAGNOSTICS

=over

=item Cluster folder not found

The provided cluster's folder was not found in the current directory.

=item Apps folder not found

The C<apps> folder was not found in the provided cluster's directory.

=item App folder not found

The provided app's folder was not found in the provided cluster's directory.

=item Could not open file

OS Error opening file.

=item Could not create file

OS Error creating a file.

=item TLD key not found

The apps helm chart in the cluster did not contain a key called C<tld>.
Add this key to the values.yaml file in the helm chart to specify the top level
domain of the cluster.

=item Failed to create Helm chart

The command C<helm create> failed to create a helm chart in the cluster's
directory.

=item Failed to seal

C<kubeseal> failed to seal the provided secret.

=item Invalid directory format

Invalid directory passed to C<seal>. Must be in the format F<cluster/app>.

This check can be disabled with the C<--skip-checks> flag.

=item Cluster context mismatch

The C<kubectl> current context is not the same as the provided cluster.

This check can be disabled with the C<--skip-checks> flag.

=back

=head1 CONFIGURATION

All operations are performed in the current working directory.

=head2 seal

The C<seal> command requires the current default kubernetes context to be the
same as the cluster where the secret is being sealed into.

If the context is different, the secret will be sealed with the wrong key and
fail to decrypt when deployed.

=head1 EXIT STATUS

B<x.pl> exits with 0 on success, and >0 if an error occurs.

=head1 DEPENDENCIES

Requires the following CPAN modules

=over

=item GetOpt::Long

=item Data::Dumper

=item Pod::Usage

=item File

=item File::Find

=item English

=item Readonly

=back

=head1 INCOMPATIBILITIES

NA

=head1 BUGS AND LIMITATIONS

NA

=head1 AUTHOR

Anshul Gupta <ansg191@anshulg.com>

=head1 LICENSE AND COPYRIGHT

The MIT License (MIT)

Copyright (c) 2024 Anshul Gupta

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=cut
