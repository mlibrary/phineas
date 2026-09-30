/**
  * Library function and standalone Jsonnet environment for managing SolrCloud
  * backups with the Solr Operator.
  *
  * This file can be imported as a local variable and called as a normal
  * function and integrated however is needed. It can also be used as the
  * source of an Argo CD application, optionally passing TLA arguments.
  *
  * To pass the arguments from an Application, specify the `directory` options
  * for the `source` (or an item in `sources`, if using multiple):
  *
  *   directory:
  *     jsonnet:
  *       tlas:
  *       - name: solrCloud
  *         value: a-different-solr
  *       - name: collections
  *         code: true
  *         value: "['one', 'two']"
  *
  * @see https://argo-cd.readthedocs.io/en/stable/user-guide/jsonnet/
  *
  * @return a 2-item array with a PVC first and the SolrBackup second
  */
function(
  solrCloud='solr',
  collections=[],
  pvcName='backups',
  repositoryName=pvcName,
  sizeLimit='10Gi',
  namespace='solr',
) [
  {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: {
      name: pvcName,
      namespace: namespace,
    },
    spec: {
      accessModes: ['ReadWriteMany'],
      resources: {
        requests: {
          storage: sizeLimit,
        },
      },
      storageClassName: 'rook-cephfs',
      volumeMode: 'Filesystem',
    },
  },

  {
    apiVersion: 'solr.apache.org/v1beta1',
    kind: 'SolrBackup',
    metadata: {
      name: pvcName,
      namespace: namespace,
    },
    spec: {
      repositoryName: repositoryName,
      solrCloud: solrCloud,
      collections: collections,
    },
  },
]
