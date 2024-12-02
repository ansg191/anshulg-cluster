#!/usr/bin/env perl

use v5.10;
use strict;
use warnings FATAL => 'all';

use Getopt::Long qw(GetOptions);
use Data::Dumper qw(Dumper);
use Pod::Usage qw(&pod2usage);
use File::Find qw(find);
use File::pushd;

# Check if the provided cluster is valid
sub check_cluster {
    my ($cluster) = @_;

    # Check if the cluster folder exists
    die "Cluster folder not found: $cluster\n" if (!-d $cluster);
    # Check if the apps folder exists
    die "Apps folder not found: $cluster/apps\n" if (!-d "$cluster/apps");

    return 0;
}

# Gets the top level domain of the cluster
sub get_tld {
    my ($cluster) = @_;

    # Check if the cluster folder exists
    check_cluster $cluster;

    # Open the cluster's values.yaml file
    open(my $fh, '<', "$cluster/apps/values.yaml") or die "Could not open file: $!";

    # Read the file line by line
    while (my $line = <$fh>) {
        # If the line contains the tld key, return the value
        if ($line =~ /^tld:\s*(.*)/) {
            close($fh);
            return $1;
        }
    }

    close($fh);
    die "tld key not found in $cluster/apps/values.yaml\n";
}

sub create_app_file {
    my ($cluster, $name) = @_;

    # Create the application file
    open(my $fh, '>', "$cluster/apps/templates/$name.yaml") or die "Could not create file: $!";

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

    print $fh $app_yaml;
    close $fh;
    system("git add $cluster/apps/templates/$name.yaml");
}

sub command_new {
    my $name;
    my $cluster;
    my $port = 80;
    my $stateful = 0;
    my $help = 0;
    GetOptions(
        "name=s"    => \$name,
        "cluster=s" => \$cluster,
        "port=i"    => \$port,
        "stateful"  => \$stateful,
        "help|?"    => \$help,
    ) or pod2usage(2);
    pod2usage(-verbose => 2) if $help != 0;

    die "Missing required option: --name\n" if (!defined($name));
    die "Missing required option: --cluster\n" if (!defined($cluster));

    check_cluster $cluster;

    print "Creating new application: `$name` in cluster: `$cluster`\n";

    # Get the TLD of the cluster
    my $tld = get_tld $cluster;

    # Create the application folder
    mkdir "$cluster/$name";

    # Create the application file
    create_app_file $cluster, $name;

    # Give the port a name
    my $port_name = "http";

    # Create service YAML
    open(my $fh, '>', "$cluster/$name/service.yaml") or die "Could not create file: $!";
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
    print $fh $service_yaml;
    close $fh;
    system("git add $cluster/$name/service.yaml");

    # Create ingress YAML
    open($fh, '>', "$cluster/$name/ingress.yaml") or die "Could not create file: $!";
    my $sec_ns = ($cluster eq "k8s") ? "traefik" : "kube-system";
    my $extra_match = ($cluster eq "rpi5") ? "|| Host(`$name.internal`)" : "";
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
    print $fh $ingress_yaml;
    close $fh;
    system("git add $cluster/$name/ingress.yaml");

    # Create certificate YAML
    open($fh, '>', "$cluster/$name/certificate.yaml") or die "Could not create file: $!";
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
    print $fh $certificate_yaml;
    close $fh;
    system("git add $cluster/$name/certificate.yaml");

    # Create deployment YAML if stateful is not set or statefulset YAML if stateful is set
    if ($stateful == 0) {
        open($fh, '>', "$cluster/$name/deployment.yaml") or die "Could not create file: $!";
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
        print $fh $deployment_yaml;
        close $fh;
        system("git add $cluster/$name/deployment.yaml");
    }
    else {
        open($fh, '>', "$cluster/$name/statefulset.yaml") or die "Could not create file: $!";
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
        print $fh $statefulset_yaml;
        close $fh;
        system("git add $cluster/$name/statefulset.yaml");
    }

    print "Application $name in $cluster created successfully\n";
}

sub command_helm {
    my $name;
    my $cluster;
    my $help = 0;
    GetOptions(
        "name=s"    => \$name,
        "cluster=s" => \$cluster,
        "help|?"    => \$help,
    ) or pod2usage(2);
    pod2usage(-verbose => 2) if $help != 0;

    die "Missing required option: --name\n" if (!defined($name));
    die "Missing required option: --cluster\n" if (!defined($cluster));

    check_cluster $cluster;
    my $tld = get_tld $cluster;

    print "Creating Helm chart for $name in $cluster\n";

    # Create the Helm chart
    {
        my $dir = pushd("$cluster");
        system("helm create $name") == 0
            or die "Failed to create Helm chart for $name in $dir\n";
        system("git add $name");
    }

    # Create the application file
    create_app_file $cluster, $name;

    # Create ingress YAML
    open(my $fh, '>', "$cluster/$name/templates/ingress_route.yaml") or die "Could not create file: $!";
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
    print $fh $ingress_yaml;
    close $fh;
    system("git add $cluster/$name/templates/ingress_route.yaml");

    # Create certificate YAML
    open($fh, '>', "$cluster/$name/templates/certificate.yaml") or die "Could not create file: $!";
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
    print $fh $certificate_yaml;
    close $fh;
    system("git add $cluster/$name/templates/certificate.yaml");

    # Append ingressRoute options to values.yaml
    open($fh, '>>', "$cluster/$name/values.yaml") or die "Could not open file: $!";
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
    print $fh $values_yaml;
    close $fh;
    system("git add $cluster/$name/values.yaml");

    print "Helm chart for $name in $cluster created successfully\n";
}

sub command_secret {
    my $name = shift(@ARGV) or die "Missing required argument: NAME\n";

    my $cluster;
    my $app;
    my $namespace;
    GetOptions(
        "cluster=s"   => \$cluster,
        "namespace=s" => \$namespace,
        "app=s"       => \$app,
    ) or pod2usage(2);

    die "Missing required option: --cluster\n" if (!defined($cluster));
    die "Missing required option: --app\n" if (!defined($app));
    $namespace = $app if (!defined($namespace));

    check_cluster $cluster;

    # Check for app folder in cluster
    die "App folder not found: $cluster/$app\n" if (!-d "$cluster/$app");

    print "Creating secret for $name/$app in $cluster/$namespace\n";

    # Call kubectl to create the secret yaml
    my $yaml = `kubectl create secret generic $name -n $namespace --dry-run=client -o yaml @ARGV`;

    # Create secret YAML
    open(my $fh, '>', "$cluster/$app/$name.unencrypted.yaml") or die "Could not create file: $!";
    print $fh $yaml;
    close $fh;

    print "Secret $name/$app in $cluster/$namespace created successfully\n";
}

sub seal_file {
    my ($file, $yes, $controller, $namespace) = @_;

    # Ask for confirmation
    if ($yes == 0) {
        print "Seal $file? [y/N] ";
        my $response = <STDIN>;
        chomp $response;
        return if ($response ne 'y');
    }

    # Remove `.unencrypted` from the file name
    my $sealed_file = $file;
    $sealed_file =~ s/\.unencrypted//;

    print "Sealing $file into $sealed_file\n";

    # Call kubeseal to seal the secret, die if the command fails
    system("kubeseal --controller-name=\"$controller\" --controller-namespace=\"$namespace\" -f $file -w $sealed_file") == 0
        or die "Failed to seal $file\n";
}

sub command_seal {
    my $namespace = 'kube-system';
    my $controller = 'sealed-secrets';
    my $yes = 0;
    my $help = 0;
    GetOptions(
        "namespace=s"  => \$namespace,
        "controller=s" => \$controller,
        "yes"          => \$yes,
        "help|?"       => \$help,
    ) or pod2usage(2);
    pod2usage(-verbose => 2) if $help != 0;

    my $dir = shift(@ARGV) or die "Missing required argument: DIR\n";

    # Get all unencrypted secret files in the directory
    my $wanted = sub {
        if (-f $_ && $_ =~ qr/\.unencrypted\.yaml$/) {
            seal_file($_, $yes, $controller, $namespace);
        }
    };

    find(\&$wanted, $dir);
}

my $subcommand = shift(@ARGV) or pod2usage(2);
if ($subcommand eq 'new') {
    command_new
}
elsif ($subcommand eq 'helm') {
    command_helm
}
elsif ($subcommand eq 'secret') {
    command_secret
}
elsif ($subcommand eq 'seal') {
    command_seal
}
# If subcommand equals help, --help or -h, print the help message
elsif ($subcommand eq 'help' || $subcommand eq '--help' || $subcommand eq '-h') {
    pod2usage(-verbose => 2)
}
else {
    print "Unknown subcommand: $subcommand\n";
    pod2usage(2);
}


__END__

=head1 NAME

./x.pl - Performs common script operations

=head1 SYNOPSIS

./x.pl [subcommand] [options]

=head1 COMMANDS

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
    -y, --yes                   Skip confirmation

=head1 DESCRIPTION

B<This program> has multiple subcommands that perform common script operations.

=cut
