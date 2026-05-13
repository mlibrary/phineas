{
  argo:: {
    // Global config for convenience defaults.
    config: {
      repoURL: error 'You must pass repoURL or set $.argo.config.repoURL to your "main" config repo to use it implicitly.',
    },

    // Convenience constants for direct use or merging
    const: {
      kube_common: 'https://github.com/mlibrary/kube-common',
    },

    /**
     * Generate a namespace with Argo-managed labels.
     *
     * A namespace generated in this way is convenient for creating a sibling
     * to an Application. This would typically be used in an app of apps to
     * manage a target namespace for a Helm release and make it visible in the
     * Argo CD dashboard.
     *
     * @deprecated since 2025-05-02; using server-side apply, all of these labels are automatically
     *     added, so nothing special is needed to create namespace objects. Also, consider using
     *     the CreateNamespace syncOption to have Argo CD create the namespace if needed.
     *
     * @param name The name of the namespace to create
     */
    namespace(name): {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: name,
        labels: {
          'pod-security.kubernetes.io/enforce': 'baseline',
          'pod-security.kubernetes.io/enforce-version': 'latest',
          'pod-security.kubernetes.io/warn': 'baseline',
          'pod-security.kubernetes.io/warn-version': 'latest',
        },
      },
    },

    /**
      * Generate a LimitRange with defaults for container resources.
      *
      * @deprecated sicne 2025-05-02; with vcluster 0.24, the status.qosClass problem that this
      *     LimitRange was added to address is resolved, and with server-side apply, the label
      *     designating the Argo CD instance is not required. If you need a LimitRange, create it
      *     within your environment definition.
      *
      * @param namespace The namespace to which the LimitRange applies
      */
    default_resources(namespace): {
      apiVersion: 'v1',
      kind: 'LimitRange',
      metadata: {
        name: 'default-container-resources',
        namespace: namespace,
      },
      spec: {
        limits: [{
          default: {
            cpu: '250m',
            'ephemeral-storage': '512Mi',
            memory: '512Mi',
          },
          defaultRequest: {
            cpu: '10m',
            'ephemeral-storage': '128Mi',
            memory: '128Mi',
          },
          type: 'Container',
        },
      ]},
    },

    // Scope for Application-related generators, call with $.argo.app.X
    app: {

      /**
       * Generate a skeletal prototype Application object for specialization.
       *
       * The prototype targets "this" cluster, the default project, applies the
       * conventional "app-of-apps" Argo CD instance label, and sets up autosync.
       * The prototype is not valid for use, as at least a repoURL must be set.
       *
       * @param name The name of the Application resource
       * @param namespace (Optional) The destination namespace (will be created if needed)
       */
      prototype(name, namespace=null): {
        local ns_mixin = if namespace == null then {} else {
          destination+: { namespace: namespace },
          syncPolicy+: { syncOptions: ['CreateNamespace=true'] },
        },

        apiVersion: 'argoproj.io/v1alpha1',
        kind: 'Application',
        metadata: {
          name: name,
          namespace: 'argocd',
        },
        spec: {
          project: 'default',
          source: {
            repoURL: error 'spec.source.repoURL must be set to a Helm chart or Git repository',
          },
          destination: {
            server: 'https://kubernetes.default.svc',
          },
          syncPolicy: {
            automated: {
              prune: false,
              selfHeal: true,
              allowEmpty: false,
            },
          },
        } + ns_mixin,
      },

      /**
       * Generate a basic Argo CD Application object sourcing a Git repository.
       *
       * Basic in this case is not an officially named concept but a description.
       * This is a generic Argo Application with typical GitOps defaults for
       * targeting "this" cluster and automatically syncing and self-healing.
       *
       * Such an app can target plain manifests, a kustomize directory, or be
       * adjusted in any way needed. If you are working with a Tanka environment,
       * an app covered in kube-common, or a Helm chart, one of the more
       * specialized functions will likely be helpful.
       *
       * @param name The name of the Application resource
       * @param namespace (Optional) The destination namespace (will be created if needed)
       * @param path The path within the repository to use as the source
       * @param repoURL The URL of the Git repository to use as the source; defaults
       *     to the global "config repo" URL for creating many apps in the same repo.
       * @param targetRevision The revision or branch in the repository to use; defaults
       *     to HEAD (of the primary branch, typicaly "main")
       */
      git(name, path, repoURL=$.argo.config.repoURL, targetRevision='HEAD', namespace=null):
        $.argo.app.prototype(name, namespace) + {
          spec+: {
            source+: {
              repoURL: repoURL,
              path: path,
              targetRevision: targetRevision,
            },
          },
        },

      /**
       * Generate an Argo CD Application object from a Tanka environment in a Git
       * repository.
       *
       * A Tanka app is very similar to a Basic app, but with the path and
       * shell configured to apply the Tanka environment in that directory.
       *
       * @param name The name of the Application resource
       * @param namespace (Optional) The destination namespace (will be created if needed)
       * @param path The path within the repository holding the Tanka environment,
       *     as would be used with `tk apply` from the repository root.
       * @param repoURL The URL of the Git repository to use as the source; defaults
       *     to the global "config repo" URL for creating many apps in the same repo.
       * @param targetRevision The revision or branch in the repository to use; defaults
       *     to HEAD (of the primary branch, typicaly "main")
       */
      tanka(name, path, repoURL=$.argo.config.repoURL, targetRevision='HEAD', namespace=null):
        $.argo.app.git(name, '.', repoURL, targetRevision) + {
          spec+: {
            source+: {
              plugin+: {
                env+: [
                  {
                    name: 'TANKA_PATH',
                    value: path,
                  },
                ],
              },
            },
          },
        },

      /**
       * Generate an Argo CD Application object to install an application from
       * the mlibrary/kube-common GitHub repository.
       *
       * There are Tanka environments in kube-common for widely used software.
       * This function makes it very simple to install one by name, rather than
       * specifying all of the details.
       *
       * @param name The name of the kube-common application to install (e.g., sealed-secrets)
       * @param branch The kube-common branch to use, stable or latest; defaults to latest
       * @param install_name The name of the Argo Application, in case it should be different
       *     from the environment name (e.g., to install multiple times)
       */
      common(name, branch='latest', install_name=name):
        $.argo.app.tanka(
          name=install_name,
          path='environments/%s' % name,
          repoURL=$.argo.const.kube_common,
          targetRevision=branch,
        ),

      /**
       * Generate an Argo CD Application object to install from a Helm chart.
       *
       * The Helm integration (or implementation) of Argo CD affords almost all
       * of the usual Helm features by mapping in some properties of the Application
       * resource. If you need to supply them, call this function and merge your
       * specializations into the returned object.
       *
       * Auto-sync is enabled by default, but pruning and self-healing are not,
       * in contrast to the other app types.
       *
       * @param repoURL The Helm repository URL
       * @param chart The name of the chart to install
       * @param targetRevision The chart version to install; defaults to HEAD,
       *     but it is recommended to use the '^x.y.z' version specifier style
       * @param name The name of the Argo Application; defaults to the chart name
       * @param namespace The namespace for the Helm release; defaults to the app name
       * @param releaseName The Helm release name to use; defaults to the app name
       *
       * @example solr: $.argo.app.helm('https://charts.bitnami.com/bitnami', 'redis', '^19.5.5')
       */
      helm(repoURL, chart, targetRevision='HEAD', name=chart, namespace=name, releaseName=name):
        $.argo.app.prototype(name) + {
          spec+: {
            source+: {
              chart: chart,
              repoURL: repoURL,
              targetRevision: targetRevision,
              helm: {
                releaseName: releaseName,
              },
            },
            destination+: {
              namespace: namespace,
            },
            syncPolicy: {
              automated: {},
            },
          },
        },

    },
  },
}
