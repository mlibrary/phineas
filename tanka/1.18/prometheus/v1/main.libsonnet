(import './config.libsonnet') +
{
  local c = $._config.prometheus,

  prometheus+: {
    prometheusServer: {
      deployment: {
        apiVersion: "apps/v1",
        kind: "Deployment",
        metadata: { name: c.prometheusServer.name },
        spec: {
          replicas: 1,
          strategy: { type: "Recreate" },
          selector: { matchLabels: { app: c.prometheusServer.name } },
          template: {
            metadata: { labels: { app: c.prometheusServer.name } },
            spec: {
              serviceAccountName: "prometheus-server",
              securityContext: {
                fsGroup: 1000,
                runAsGroup: 1000,
                runAsUser: 1000,
                runAsNonRoot: true,
              },

              containers: [{
                name: "configmap-reload",
                image: c.prometheusServer.reloadImage,
                args: [
                  "--volume-dir=/etc/config",
                  "--webhook-url=http://127.0.0.1:9090/-/reload",
                ],
                volumeMounts: [{
                  name: "config",
                  mountPath: "/etc/config",
                  readOnly: true,
                }],
              }, {
                name: "prometheus",
                image: c.prometheusServer.image,

                args: [
                  "--storage.tsdb.retention.time=15d",
                  "--config.file=/etc/config/prometheus.yml",
                  "--storage.tsdb.path=/data",
                  "--web.console.libraries=/etc/prometheus/console_libraries",
                  "--web.console.templates=/etc/prometheus/consoles",
                  "--web.enable-lifecycle",
                ],

                ports: [{
                  containerPort: 9090,
                  name: "http",
                  protocol: "TCP",
                }],

                livenessProbe: {
                  initialDelaySeconds: 30,
                  timeoutSeconds: 30,
                  httpGet: {
                    path: "/-/healthy",
                    port: 9090,
                  },
                },

                readinessProbe: {
                  initialDelaySeconds: 30,
                  timeoutSeconds: 30,
                  httpGet: {
                    path: "/-/ready",
                    port: 9090,
                  },
                },

                volumeMounts: [{
                  name: "config",
                  mountPath: "/etc/config",
                }, {
                  name: "storage",
                  mountPath: "/data",
                }, {
                  name: "tls",
                  mountPath: "/tls",
                }],
              }],

              volumes: [{
                name: "config",
                configMap: { name: c.prometheusServer.name },
              }, {
                name: "storage",
                persistentVolumeClaim: { claimName: c.prometheusServer.name },
              }, {
                name: "tls",
                secret: { secretName: c.prometheusServer.name },
              }],
            },
          },
        },
      },

      service: {
        apiVersion: "v1",
        kind: "Service",
        metadata: { name: c.prometheusServer.name },
        spec: {
          selector: { app: c.prometheusServer.name },
          ports: [{
            name: "http",
            port: 9090,
            targetPort: 9090,
            protocol: "TCP",
          }],
        },
      },

      config: {
        apiVersion: "v1",
        kind: "ConfigMap",
        metadata: { name: c.prometheusServer.name },
        data: {
          "alerting_rules.yml": c.prometheusServer.alerting_rules_file,
          "recording_rules.yml": c.prometheusServer.recording_rules_file,

          "prometheus.yml": std.manifestYamlDoc({
            global: {
              scrape_interval: c.prometheusServer.scrape_interval,
              external_labels: { team: c.name },
            },

            rule_files: [
              "/etc/config/recording_rules.yml",
              "/etc/config/alerting_rules.yml",
            ],

            alerting: { alertmanagers: [{
              static_configs: [{ targets: c.prometheusServer.alertmanagers }],
              scheme: "https",
              tls_config: {
                ca_file: "/tls/ca.crt",
                cert_file: "/tls/tls.crt",
                key_file: "/tls/tls.key",
              },
            }] },

            scrape_configs: [{
              job_name: "prometheus",
              static_configs: [{ targets: ["localhost:9090"] }],
            }, {
              job_name: "pods",
              kubernetes_sd_configs: [{
                role: "pod",
                namespaces: { names: c.prometheusServer.namespaces },
              }],
              relabel_configs: [{
                action: "keep",

                // ignore pod unless mlibrary.io/prometheus-scrape: "true"
                source_labels: [
                  "__meta_kubernetes_pod_annotation_mlibrary_io_prometheus_scrape",
                ],
                regex: "true",
              }, {
                action: "replace",
                target_label: "__metrics_path__",

                // mlibrary.io/prometheus-path: "..."
                source_labels: [
                  "__meta_kubernetes_pod_annotation_mlibrary_io_prometheus_path",
                ],
                regex: "(.+)",
              }, {
                action: "replace",
                target_label: "__address__",

                // mlibrary.io/prometheus-port: "1234"
                source_labels: [
                  "__address__",
                  "__meta_kubernetes_pod_annotation_mlibrary_io_prometheus_port",
                ],

                // (172.16.x.y)(:<old port>);(<new port>)
                regex: "([^:]+)(?::\\d+)?;(\\d+)",

                // 172.16.x.y:<new port>
                replacement: "$1:$2",
              }, {
                action: "labelmap",
                regex: "__meta_kubernetes_pod_label_(.+)",
              }, {
                action: "replace",
                target_label: "kubernetes_namespace",
                source_labels: [
                  "__meta_kubernetes_namespace",
                ],
              }, {
                action: "replace",
                target_label: "kubernetes_pod_name",
                source_labels: [
                  "__meta_kubernetes_pod_name",
                ],
              }],
            }] +
            c.prometheusServer.scrape_configs +
            if c.pushgateway.enabled then [{
              job_name: c.pushgateway.name,
              honor_labels: true,
              static_configs: [{ targets: ["%s:9091" % c.pushgateway.name] }],
            }] else [],
          }),
        },
      },

      storage: {
        apiVersion: "v1",
        kind: "PersistentVolumeClaim",
        metadata: { name: c.prometheusServer.name },
        spec: {
          accessModes: ["ReadWriteOnce"],
          storageClassName: c.prometheusServer.storageClass,
          resources: { requests: { storage: c.prometheusServer.storage } },
        },
      },
    },

    pushgateway: if c.pushgateway.enabled then {
      deployment: {
        apiVersion: "apps/v1",
        kind: "Deployment",
        metadata: { name: c.pushgateway.name },
        spec: {
          replicas: 1,
          strategy: { type: "Recreate" },
          selector: { matchLabels: { app: c.pushgateway.name } },
          template: {
            metadata: { labels: { app: c.pushgateway.name } },
            spec: {
              containers: [{
                name: "pushgateway",
                image: c.pushgateway.image,

                ports: [{
                  containerPort: 9091,
                  name: "http",
                  protocol: "TCP",
                }],

                livenessProbe: {
                  initialDelaySeconds: 30,
                  timeoutSeconds: 30,
                  httpGet: {
                    path: "/-/healthy",
                    port: 9091,
                  },
                },

                readinessProbe: {
                  initialDelaySeconds: 30,
                  timeoutSeconds: 30,
                  httpGet: {
                    path: "/-/ready",
                    port: 9091,
                  },
                },
              }],
            },
          },
        },
      },

      service: {
        apiVersion: "v1",
        kind: "Service",
        metadata: { name: c.pushgateway.name },
        spec: {
          selector: { app: c.pushgateway.name },
          ports: [{
            name: "http",
            port: 9091,
            targetPort: 9091,
            protocol: "TCP",
          }],
        },
      },
    } else {},

    grafana: {
      deployment: {
        apiVersion: "apps/v1",
        kind: "Deployment",
        metadata: { name: c.grafana.name },
        spec: {
          replicas: 1,
          strategy: { type: "Recreate" },
          selector: { matchLabels: { app: c.grafana.name } },
          template: {
            metadata: { labels: { app: c.grafana.name } },
            spec: {
              securityContext: {
                fsGroup: 1000,
                runAsGroup: 1000,
                runAsUser: 1000,
                runAsNonRoot: true,
              },

              containers: [{
                name: "grafana",
                image: c.grafana.image,

                ports: [{
                  containerPort: 3000,
                  name: "http",
                  protocol: "TCP",
                }],

                livenessProbe: {
                  initialDelaySeconds: 5,
                  httpGet: {
                    path: "/api/health",
                    port: 3000,
                  },
                },

                resources: { limits: {
                  cpu: c.grafana.cpuLimit,
                  memory: c.grafana.memoryLimit,
                }},

                volumeMounts: [{
                  name: "config",
                  subPath: "grafana.ini",
                  mountPath: "/etc/grafana/grafana.ini",
                }, {
                  name: "storage",
                  mountPath: "/var/lib/grafana",
                }],
              }],

              volumes: [{
                name: "config",
                configMap: { name: c.grafana.name },
              }, {
                name: "storage",
                persistentVolumeClaim: { claimName: c.grafana.name },
              }],
            },
          },
        },
      },

      service: {
        apiVersion: "v1",
        kind: "Service",
        metadata: { name: c.grafana.name },
        spec: {
          selector: { app: c.grafana.name },
          ports: [{
            name: "http",
            port: 80,
            targetPort: 3000,
            protocol: "TCP",
          }],
        },
      },

      ingress: {
        apiVersion: "extensions/v1beta1",
        kind: "Ingress",
        metadata: {
          name: c.grafana.name,
          annotations: {
            "cert-manager.io/cluster-issuer": c.grafana.clusterIssuer,
          },
        },

        spec: {
          rules: [{
            host: c.grafana.host,
            http: { paths: [{
              path: "/",
              backend: {
                serviceName: c.grafana.name,
                servicePort: 80,
              },
            }] },
          }],

          tls: [{
            secretName: "%s-tls" % c.grafana.name,
            hosts: [ c.grafana.host ],
          }],
        },
      },

      config: {
        apiVersion: "v1",
        kind: "ConfigMap",
        metadata: { name: c.grafana.name },
        data: { "grafana.ini": std.manifestIni({
          sections: {
            server: { root_url: "https://%s" % c.grafana.host },

            auth: {
              oauth_auto_login: "true",
              disable_login_form: "true",
              disable_signout_menu: "false",
            },

            "auth.generic_oauth": {
              name: "Dex",
              enabled: "true",
              client_id: c.dexClient,
              client_secret: c.dexSecret,
              allow_sign_up: "true",
              auth_url: "%s/auth" % c.dexUrl,
              token_url: "%s/token" % c.dexUrl,
              api_url: "%s/userinfo" % c.dexUrl,
              scopes: "openid profile email groups",

              local userOnTeam(team) = "contains(groups[*], '%s')" % team,
              local userOnAnyOf(teams) = std.join(" || ", [userOnTeam(team) for team in teams]),
              role_attribute_path: "(%s) && 'Admin' || 'None'" % userOnAnyOf(c.githubTeams),
            },
          },
        }) },
      },

      storage: {
        apiVersion: "v1",
        kind: "PersistentVolumeClaim",
        metadata: { name: c.grafana.name },
        spec: {
          accessModes: ["ReadWriteOnce"],
          storageClassName: c.grafana.storageClass,
          resources: { requests: { storage: c.grafana.storage } },
        },
      },
    },
  }
}
