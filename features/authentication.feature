Feature: authentication
  We need to implement our own auth system, likely based on OAuth, that
  manages tokens and ideally gives the option to download TTL'd
  .kube/config files with the right tokens in place.

  For developers looking only to deploy new releases, we should provide
  enough indirect interfaces that we likely won't need to worry about
  kubernetes's RBAC model (I'm talking here essentially about our own
  application/service that does nothing other than deploy new releases).

  For anyone needing direct access to kubernetes however, we'll need to
  generate and manage tokens that kubernetes can understand and verify.
