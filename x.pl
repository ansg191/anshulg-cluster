#!/usr/bin/env perl

use v5.10;
use strict;
use warnings FATAL => 'all';

use Getopt::Long qw(GetOptions);
use Data::Dumper qw(Dumper);
use Pod::Usage qw(&pod2usage);

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
        "stateful" => \$stateful,
        "help|?"    => \$help,
    ) or pod2usage(2);
    pod2usage(-verbose => 2) if $help != 0;

    die "Missing required option: --name\n" if (!defined($name));
    die "Missing required option: --cluster\n" if (!defined($cluster));

    print "Creating new application: `$name` in cluster: `$cluster`\n";

    # Look for the folder $cluster in the current directory
    die "Cluster folder not found: $cluster\n" if (!-d $cluster);
    # Look for "apps" folder in the cluster folder
    die "Apps folder not found: $cluster/apps\n" if (!-d "$cluster/apps");

    # Create the application folder
    mkdir "$cluster/$name";
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
    path: rpi5/$name
END_YAML

    print $fh $app_yaml;
    close $fh;
    system("git add $cluster/apps/templates/$name.yaml");

    # Create service YAML
    open($fh, '>', "$cluster/$name/service.yaml") or die "Could not create file: $!";
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
      targetPort: $port
  type: ClusterIP
END_YAML
    print $fh $service_yaml;
    close $fh;
    system("git add $cluster/$name/service.yaml");

    # Create ingress YAML
    open($fh, '>', "$cluster/$name/ingress.yaml") or die "Could not create file: $!";
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
      match: Host(`$name.local`)
      middlewares:
        - name: security-headers
          namespace: kube-system
      services:
        - name: $name
          port: 80
  tls:
    secretName: $name-cert-tls
    domains:
      - main: $name.local
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
  commonName: $name.local
  dnsNames:
    - $name.local
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
      - rpi5
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
          env: []
          # resources:
          #   requests:
          #     cpu: 250m
          #     memory: 500Mi
          #   limits:
          #     memory: 1Gi
          # livenessProbe:
          #   httpGet:
          #     port: 7878
          #     path: /ping
          #   initialDelaySeconds: 30
          #   periodSeconds: 30
          #   timeoutSeconds: 5
          #   failureThreshold: 3
          # readinessProbe:
          #   httpGet:
          #     port: 7878
          #     path: /ping
          #   periodSeconds: 10
          #   timeoutSeconds: 5
          #   failureThreshold: 3
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
          # resources:
          #   requests:
          #     cpu: 250m
          #     memory: 500Mi
          #   limits:
          #     memory: 1Gi
          # livenessProbe:
          #   httpGet:
          #     port: 7878
          #     path: /ping
          #   initialDelaySeconds: 30
          #   periodSeconds: 30
          #   timeoutSeconds: 5
          #   failureThreshold: 3
          # readinessProbe:
          #   httpGet:
          #     port: 7878
          #     path: /ping
          #   periodSeconds: 10
          #   timeoutSeconds: 5
          #   failureThreshold: 3
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

my $subcommand = shift(@ARGV);
if ($subcommand eq 'new') {
    command_new
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

Create a new application.

 Options:
     -n, --name=NAME        The name of the application
     -c, --cluster=CLUSTER  The cluster to deploy the application to
     -p, --port=PORT        The port to expose the application on (default: 80)
     -s, --stateful         Create a stateful application (default: false)

=head1 DESCRIPTION

B<This program> has multiple subcommands that perform common script operations.

=cut
