(import 'phineas/argo.libsonnet') +
{
  solr:: {
    /** References for Solr Operator and SolrCloud charts */
    charts: {
      operator: {
        repo: 'https://solr.apache.org/charts',
        chart: 'solr-operator',
        version: '0.9.1',
      },
      cloud: {
        repo: 'https://solr.apache.org/charts',
        chart: 'solr',
        version: '0.9.1',
      },
    },

    /** Default configuration to be cloned and extended if customizations are needed */
    config: {
      image: {
        tag: '9.10',
      },

      /** Resources for each SolrCloud node; used as `podOptions.resources` values */
      nodeResources: {
        requests: {
          cpu: '500m',
          memory: '1Gi',
        },
        limits: {
          cpu: '1000m',
          memory: '2Gi',
        },
      },

      /** Storage configuration for Solr; used as `dataStorage` values; see $.solr.dataStorage */
      dataStorage: $.solr.dataStorage.cluster,

      /** ZooKeeper storage configuration; used as `zk` values; see $.solr.zkStorage */
      zkStorage: $.solr.zkStorage.cluster,

      /** Options for the Solr process; used as `solrOptions` values */
      solrOptions: {
        // Allow bothSolr 8 and Solr 9 PKI protocols by default to support migration
        javaOpts: '-Dsolr.pki.sendVersion=v1 -Dsolr.pki.acceptVersions=v1,v2',
        // Include analysis-extras by default for ICU extensions
        solrModules: ['analysis-extras'],
        security: {
          authenticationType: 'Basic',
        },
      },

      /** 
        * Backup configuration; if `enabled` is true, a PVC (RWX) will be created and a
        * backupRepository will be configured to point to it. Collections that are listed will
        * have a SolrBackup configured for them.
        *
        * If you have a more specialized backup scenario, it is recommended to leave `enabled` set
        * to false, merge your Helm values into the application object yielded by $.solr.cloud(),
        * and create SolrBackup resources as needed.
        */
      backups: {
        enabled: true,
        pvc: {
          name: 'backups',
          sizeLimit: '10Gi',
        },
        collections: [],
      }
    },

    /**
      * Solr data storage preset configurations to be used by reference and optionally extended.
      *
      * These named presets are here to capture localizations like the storage classes and
      * useful default sizes. They map to the `solr` chart values, which then map to the SolrCloud
      * CRD fields, so there are multiple layers of indirection to consider. Consult the
      * documentation for the chart and the CRD if you need other options.
      *
      * Our options are:
      * 
      *   - node:    the storage layer itself is node-attached and unreplicated, relying
      *              on application replication for data resiliency; appropriate for large
      *              collections in production scenarios; requires manual provisioning
      *   - cluster: the storage layer is replicated within the cluster, allowing pods to
      *              be scheduled on any node and reach their PVC; appropriate for moderate
      *              collections and where the extra copies and performance overhead do not
      *              pose concern; provisioned automatically
      *   - memory:  volatile storage suitable for testing configuration options or transient
      *              experimentation; provisioned as RAM disk by default, so performance will
      *              be the best available, but count against memory usage and quotas
      */
    dataStorage: {
      node: {
        type: 'persistent',
        capacity: '20Gi',
        persistent: {
          pvc: {
            storageClassName: 'local-storage',
          },
        },
      },
      cluster: {
        type: 'persistent',
        capacity: '10Gi',
        persistent: {
          pvc: {
            storageClassName: 'rook-ceph-block',
          },
        },
      },
      memory: {
        type: 'ephemeral',
        capacity: '5Gi',
        emptyDir: {
          medium: 'Memory',
        }
      },
    },

    /**
      * ZooKeeper storage preset configurations to be used by reference and optionally extended.
      *
      * As with the Solr dataStorage above, these presets offer convenience for choosing a default
      * configuration with appropriate local details and sizes without dealing with the names and
      * shapes of the Solr/ZooKeeper helm chart and CRD options for these. Our options are:
      *
      *  - cluster: the storage layer is replicated and available from any node; it is provisioned
      *             automatically as a PVC; appropriate for all use cases
      *  - memory:  the storage is volatile, in memory; appropriate only for testing or other
      *             transient scenarios
      */
    zkStorage: {
      cluster: {
        provided: {
          persistence: {
            spec: {
              storageClassName: 'rook-ceph-block',
              resources: {
                requests: {
                  storage: '100Mi',
                },
                limits: {
                  storage: '200Mi',
                },
              },
            },
          },
        },
      },
      memory: {
        provided: {
          ephemeral: {
            emptydirvolumesource: {
              medium: 'Memory',
              sizeLimit: '200Mi',
            },
          },
        },
      },
    },

    /**
      * Install the Solr Operator / SolrCloud CRDs.
      *
      * The CRDs are installed from vendored YAML rather than via Helm based on the recommendation
      * of the Solr Operator maintainers. They are installed as an Argo CD application with a lower
      * sync-wave value than the operator to allow for upgrading them in one configuration change.
      *
      * @param version The chart version for the operator/CRDs; ignored if path is supplied
      * @param path The path to the directory containing the CRD YAML (all files will be sourced)
      * @param repoURL The repository URL for the CRDs; defaults to phineas
      * @param targetRevision The revision/tag to use (to insure against drift); defaults to HEAD
      *
      * @example $.solr.crds('0.9.1')
      */
    crds(
      version=$.solr.charts.operator.version,
      path='lib/phineas/solr/crds/%s' % version,
      repoURL=$.phineas.repoURL,
      targetRevision=$.phineas.revision,
    ):
      $.argo.app.git(
        name='solr-crds',
        path=path,
        repoURL=repoURL,
        targetRevision=targetRevision,
      ) + {
        metadata+: {
          annotations+: {
            'argocd.argoproj.io/sync-wave': '-10',
          }
        },
        spec+: { syncPolicy+: { syncOptions+: ['ServerSideApply=true'] } }
      },

    /**
      * Install the Solr Operator by Helm chart.
      *
      * This convenience form allows intalling the Solr Operator with a specific
      * version, name, and namespace while offering typical defaults. Note that
      * you should take care about the version; there may be required steps when
      * upgrading. The default version here and the SolrCloud instance generated by
      * $.solr.cloud() will be compatible, but you may need to synchronize customizations.
      *
      * @param chartVersion the chart version to use; note this typically matches the operator version
      * @param name the name of the Argo CD application, also used for the Helm release name
      * @param namespace the namespace to house the operator
      *
      * @example operator: $.solr.operator('0.9.1')
      */
    operator(chartVersion=$.solr.charts.operator.version, name='solr-operator', namespace='solr'):
      $.argo.app.helm(
        repoURL=$.solr.charts.operator.repo,
        chart=$.solr.charts.operator.chart,
        targetRevision=chartVersion,
        name=name,
        namespace=namespace,
      ) + {
        metadata+: {
          annotations+: {
            'argocd.argoproj.io/sync-wave': '0',
          },
        },
        spec+: {
          syncPolicy+: { syncOptions+: ['ServerSideApply=true'] },
          source+: {
            helm+: {
              values: std.manifestYamlDoc({
                'metrics.enable': false,
              }),
            },
          },
        },
      },

    /**
      * Install a SolrCloud instance by Helm Chart.
      *
      * The SolrCloud CRD and Helm chart do not match exactly between the spec and values formats.
      * Consult both if you need to apply customizations, starting with the chart values. The
      * most convenient way to do that is typically on ArtifactHub. The most convenient way to
      * explore the CRD is typically with `kubectl explain SolrCloud.spec...` on a cluster where the
      * CRD is installed.
      *
      * The default config options provide a convenience form beyond even the Helm values;
      * see $.solr.config above for some preset option sets that you may wish to use directly or
      * with minor changes. The most likely customizations would be to list collections for backup
      * or to adjust the nodeResources upward for demanding applications.
      *
      * Note that multiple collections can and should reside in the same SolrCloud cluster, unless
      * there is a meaningful configuration incompatibility required for different applications in
      * the same Kubernetes cluster.
      *
      * @param config the options for this SolrCloud cluster; see $.solr.config
      * @param chartVersion the version of the Solr chart to use (typically matches the Operator chart)
      * @param name the name of the Solr Cloud instance; appears as the name of the Argo CD Application,
      *             helm release, and the SolrCloud itself (in hostnames/services).
      * @param namespace the namespace for installation
      */
    cloud(config=$.solr.config, chartVersion=$.solr.charts.cloud.version, name='solr', namespace='solr'): [
      local helm = $.argo.source.helm(
        repoURL=$.solr.charts.cloud.repo,
        chart=$.solr.charts.cloud.chart,
        targetRevision=chartVersion,
        releaseName=name
      ) + {
        helm+: {
          values: std.manifestYamlDoc({
            image: {
              tag: config.image.tag
            },
            podOptions: {
              resources: config.nodeResources,
            },
            backupRepositories: if config.backups.enabled then [{
              name: 'in-cluster',
              volume: {
                source: {
                  persistentVolumeClaim: {
                    claimName: config.backups.pvc.name,
                  }
                }
              }
            }] else [],
            solrOptions: config.solrOptions,
            dataStorage: config.dataStorage,
            zk: config.zkStorage,
          })
        }
      };

      local backups = if config.backups.enabled then
        $.argo.source.git(
          repoURL=$.phineas.repoURL,
          path='lib/phineas/solr/backups',
          targetRevision=$.phineas.revision,
        ) + {
          directory: {
            jsonnet: {
              tlas: [
                {
                  name: 'solrCloud',
                  value: name,
                },
                {
                  name: 'collections',
                  value: std.manifestJsonEx(config.backups.collections, '', '', ':'),
                  code: true,
                },
                {
                  name: 'pvcName',
                  value: config.backups.pvc.name,
                },
                {
                  name: 'sizeLimit',
                  value: config.backups.pvc.sizeLimit,
                },
                {
                  name: 'namespace',
                  value: namespace,
                },
              ],
            },
          },
        }
        else null;

      local sources = std.filter(function(x) x != null, [helm, backups]);

      $.argo.app.multisource(name, namespace=namespace, sources=sources) + {
        metadata+: {
          annotations+: {
            'argocd.argoproj.io/sync-wave': '10',
          },
        },
        spec+: { syncPolicy+: { syncOptions+: ['ServerSideApply=true'] } },
      },
    ],

  },

  /*
  metrics: {
    apiVersion: 'solr.apache.org/v1beta1',
    kind: 'SolrPrometheusExporter',
    metadata: {
      name: 'solr-metrics',
      namespace: 'solr',
    },
    spec: {
      solrReference: {
        basicAuthSecret: 'solr-solrcloud-basic-auth',
        cloud: {
          name: 'solr',
          namespace: 'solr',
        },
      },
      image: {
        tag: $._config.solrImage.tag,
      },
      customKubeOptions: {
        podOptions: {
          annotations: {
            'prometheus.io/port': '8080',
            'prometheus.io/path': '/metrics',
            'prometheus.io/scrape': 'true',
            'prometheus.io/scheme': 'http',
          },
        },
      },
    },
  },
  */
}
