# Image Safety
# ------------
#

# Check images do not have "latest" tag, whether it is explicit or implicit

# FIXME : manage "toto.com:9090/mysql:latest",

package kubernetes.validating.images

import future.keywords.in

# If image contains do not contains ":", returns [image, "latest"]
split_image(image) = [image, "latest"] {
	not contains(image, ":")
}

# If image contains ":", returns [image_name, tag]
split_image(image) = [image_name, tag] {
	[image_name, tag] = split(image, ":")
}

deny[msg] {
    input.request.kind.kind == "Pod"
    some container in input.request.object.spec.containers
	[image_name, "latest"] = split_image(container.image)
	msg = sprintf("%s in the Pod %s has an image, %s, using the latest tag", [container.name, input.request.object.metadata.name, image_name])
}
