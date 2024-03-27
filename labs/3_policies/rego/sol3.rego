package kubernetes.validating.images

import future.keywords.contains
import future.keywords.if
import future.keywords.in

deny contains msg if {
        input.request.kind.kind == "Pod"

        # The `some` keyword declares local variables. This rule declares a variable
        # called `container`, with the value any of the input request's spec's container
        # objects. It then checks if the container object's `"image"` field does not 
        # start with "hooli.com/".
        some container in input.request.object.spec.containers
        endswith(container.image, ":latest")
    msg := sprintf("Tag 'latest' is forbidden for image %v", [container.image])
}

deny contains msg if {
   input.request.kind.kind == "Pod"
   some container2 in input.request.object.spec.containers
   not contains(container2.image, ":")
   msg := sprintf("Image must contains a tag for image %v", [container2.image])
}
