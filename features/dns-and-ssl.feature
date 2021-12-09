Feature: provisioning DNS and SSL
  I'm not sure that this is a feature that needs documenting here. At
  least, not until we have more experience with Kubernetes Ingresses,
  what they let us do, and how easy it is to do it.

  In the end, most (if not all) public-facing services should be
  accessed through an ingress. We can have as many ingresses as we want,
  but each needs its own unique IP address, so I don't see why we'd want
  more than one per cluster.

  I imagine A&E would control the ingress, and adding DNS/SSL would be
  part of provisioning. Given that we'll also need to set up DNS through
  bind on sherry, I'm not sure how much of this we want to iron out
  right now.
