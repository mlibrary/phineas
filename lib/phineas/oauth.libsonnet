{
  oauth:: {
    /**
      * Generate a complete oauth2-proxy (OIDC authenticator) installation.
      *
      * This will set up a pod, service, and ingress called oauth2-proxy. The pod and service
      * operate on the default port of 4180, and the ingress maps 80/443 to it. This can be
      * used with the ingress-nginx annotations to use the sidecar authentication pattern.
      *
      * If using a direct ingress, the $host plcaeholder can be used in the annotations. If
      * proxying through Cloudflare, either a rule will be needed to allow the traffic loop
      * from the ingress controller to the proxy service, or an in-cluster hostname and port
      * are required (with special note regarding vcluster that this name must be resolvable
      * within the HOST cluster).
      *
      * As an example of the annotations:
      *
      *   nginx.ingress.kubernetes.io/auth-url: 'https://$host/oauth2/auth'
      *   nginx.ingress.kubernetes.io/auth-signin: 'https://$host/oauth2/start?rd=$escaped_request_uri'
      *
      * If needing to keep the request in-cluster, the auth-url (only) will be changed to HTTP and
      * targeting the hostname and port of the service. For example:
      *
      *   nginx.ingress.kubernetes.io/auth-url: 'http://oauth2-proxy-x-sample-x-vcluster.sample-cluster.svc.cluster.local:4180/oauth2/auth'
      *
      * @param namespace the namespace in which to run the proxy
      * @param hostname the hostname for the oauth2 ingress (usually same as app)
      * @param proxy_config the expanded oauth2-proxy.cfg config file as a string
      *
      * @example $.oauth.proxy(
      *            namespace='preview',
      *            hostname='preview.findingaids.lib.umich.edu',
      *            proxy_config=importstr './oauth2-proxy.cfg'
      *          )
      */
    proxy(namespace, hostname, proxy_config): {
      ingress: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
          name: 'oauth2-proxy',
          namespace: namespace,
          annotations: {
            'cert-manager.io/cluster-issuer': 'letsencrypt',
          },
        },
        spec: {
          rules: [{
            host: hostname,
            http: {
              paths: [{
                path: '/oauth2',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: 'oauth2-proxy',
                    port: { number: 4180 },
                  },
                },
              }],
            },
          }],
          tls: [{
            hosts: [hostname],
            secretName: 'web-tls',
          }],
        },
      },

      oauth2_proxy: {
        secret: {
          kind: 'Secret',
          apiVersion: 'v1',
          metadata: {
            name: 'oauth2-proxy-cfg',
            namespace: namespace,
          },
          stringData: {
            'oauth2-proxy.cfg': proxy_config,
          },
        },
      },

      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          labels: {
            'app.kubernetes.io/name': 'oauth2-proxy',
          },
          name: 'oauth2-proxy',
          namespace: namespace,
        },
        spec: {
          replicas: 1,
          selector: {
            matchLabels: { 'app.kubernetes.io/name': 'oauth2-proxy' },
          },
          template: {
            metadata: {
              labels: { 'app.kubernetes.io/name': 'oauth2-proxy' },
            },
            spec: {
              containers: [{
                args: [
                  '--config=/etc/oauth2-proxy/oauth2-proxy.cfg',
                  '--upstream=file:///dev/null',
                  '--http-address=0.0.0.0:4180',
                ],
                image: 'quay.io/oauth2-proxy/oauth2-proxy:v7.6.0',
                imagePullPolicy: 'IfNotPresent',
                name: 'oauth2-proxy',
                ports: [{
                  containerPort: 4180,
                  protocol: 'TCP',
                }],
                volumeMounts: [{
                  name: 'oauth2-proxy-cfg',
                  mountPath: '/etc/oauth2-proxy',
                  readOnly: true,
                }],
              }],
              volumes: [{
                name: 'oauth2-proxy-cfg',
                secret: {
                  secretName: 'oauth2-proxy-cfg',
                },
              }],
            },
          },
        },
      },
      service: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
          labels: {
            'app.kubernetes.io/name': 'oauth2-proxy',
          },
          name: 'oauth2-proxy',
          namespace: namespace,
        },
        spec: {
          ports: [
            {
              name: 'http',
              port: 4180,
              protocol: 'TCP',
              targetPort: 4180,
            },
          ],
          selector: {
            'app.kubernetes.io/name': 'oauth2-proxy',
          },
        },
      },
    },
  },
}
