{
  cloudflare:: {
    config: {
      haproxy: {
        image: 'haproxy',
        tag: '3.1',
      },
    },

    /**
      * Generate an HAProxy instance to pass the client IP from Cloudflare headers to an application.
      *
      * This small reverse proxy serves only to validate that the incoming connection is from a
      * recognized Cloudflare proxy IP range and translate the headers. Your public Ingress/Gateway
      * should target the `haproxy-cloudflare` service on port 8080, rather than your application
      * directly.
      *
      * The X-Forwarded-For header will be set to the actual client IP address if the request is
      * proxied. In the case of requests from Cloudflare Workers, it will be set to a fixed, unroutable
      * marker address (240.36.0.103, chosen to roughly resemble the actual IPv6 source address of
      * 2a06:98c0:3600::103) with the User-Agent modified to include the specific worker ID.
      *
      * The default behavior is to require that all requests are proxied through Cloudflare, but
      * there is an option to allow direct requests. This can be useful when first enabling proxying
      * for a site, while the DNS changes are still propagating, or for diagnosing Cloudflare-related
      * issues by using local hosts entries or something like `curl --resolve ...`.
      *
      * @param namespace the namespace in which to install HAProxy
      * @param service the target service for the application
      * @param port the target port of the application service
      * @param require_proxy [Optional] whether to enforce that all requests come from Cloudflare
      * @param config [Optional] configuration details for the HAProxy container/image, see $.cloudflare.config
      *
      * @example $.cloudflare.haproxy(
      *            namespace='production',
      *            service='app'
      *            port=3000
      *          )
      */
    haproxy(namespace, service, port, require_proxy=true, config=$.cloudflare.config): {
      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          labels: {
            'app.kubernetes.io/component': 'load-balancer',
            'app.kubernetes.io/name': 'haproxy',
          },
          name: 'haproxy-cloudflare',
          namespace: namespace,
        },
        spec: {
          replicas: 1,
          selector: {
            matchLabels: {
              'app.kubernetes.io/name': 'haproxy',
            },
          },
          template: {
            metadata: {
              labels: {
                'app.kubernetes.io/component': 'load-balancer',
                'app.kubernetes.io/name': 'haproxy',
              },
            },
            spec: {
              containers: [
                {
                  image: '%s:%s' % [config.haproxy.image, config.haproxy.tag],
                  name: 'haproxy',
                  ports: [
                    {
                      containerPort: 8080,
                      protocol: 'TCP',
                    },
                  ],
                  resources: {
                    limits: {
                      cpu: '250m',
                      memory: '256Mi',
                    },
                    requests: {
                      cpu: '100m',
                      memory: '64Mi',
                    },
                  },
                  volumeMounts: [
                    {
                      mountPath: '/usr/local/etc/haproxy',
                      name: 'haproxy-cloudflare',
                      readOnly: true,
                    },
                  ],
                },
              ],
              volumes: [
                {
                  name: 'haproxy-cloudflare',
                  configMap: {
                    name: 'haproxy-cloudflare',
                    items: [
                      {
                        key: 'haproxy.cfg',
                        path: 'haproxy.cfg',
                      },
                      {
                        key: 'ips-v4.txt',
                        path: 'ips-v4.txt',
                      },
                    ],
                  },
                },
              ],
            },
          },
        },
      },

      service: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
          labels: {
            'app.kubernetes.io/component': 'load-balancer',
            'app.kubernetes.io/name': 'haproxy',
          },
          name: 'haproxy-cloudflare',
          namespace: namespace,
        },
        spec: {
          ports: [{
            name: 'haproxy',
            port: 8080,
          }],
          selector: {
            'app.kubernetes.io/name': 'haproxy',
          },
        },
      },

      config: {
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          name: 'haproxy-cloudflare',
          namespace: namespace,
        },
        data: {
          'haproxy.cfg': $.cloudflare.config_file(service, port, require_proxy),
          'ips-v4.txt': importstr './cloudflare-ips-v4.txt',
        },
      },
    },

    /**
      * Helper function to generate the HAProxy config file; not likely to be called directly.
      *
      * This config is rather straightforward, with no options other than whether to enforce that
      * any request is proxied through Cloudflare.
      */
    config_file(service, port, require_proxy=true): |||
      global
        log stdout format raw daemon debug

      defaults
        mode http
        option httplog
        log global
        timeout client 10s
        timeout connect 5s
        timeout server 60s 
        timeout http-request 10s

      frontend %(service)s-frontend
        bind :8080
        default_backend %(service)s-backend

      backend %(service)s-backend
        server %(service)s %(service)s:%(port)d

      acl cloudflare_proxied req.hdr(X-Forwarded-For) -m ip -n -f /usr/local/etc/haproxy/ips-v4.txt
      acl cloudflare_connecting_ip req.hdr(CF-Connecting-IP) -m found
      acl cloudflare_worker req.hdr(CF-Worker) -m found

      http-request set-header X-Forwarded-For %%[req.hdr(CF-Connecting-IP)] if cloudflare_proxied cloudflare_connecting_ip
      http-request set-header X-Forwarded-For 240.36.0.103 if cloudflare_proxied cloudflare_worker
      http-request replace-header User-Agent (.*) "Cloudflare Worker (%%[req.hdr(CF-Worker)]) - \1" if cloudflare_proxied cloudflare_worker
      %(require_proxy)s
    ||| % {
      service: service,
      port: port,
      require_proxy: if require_proxy then 'http-request deny unless cloudflare_proxied' else ''
    },
  },
}
