# Image Safety
# ------------
#

# Check images do not have "latest" tag, whether it is explicit or implicit

# FIXME: mak it work!

package kubernetes.validating.images

import future.keywords.in

requested_images = {img | img := input.request.object.spec.containers[_].image}

deny[msg] {
	input.request.kind.kind == "Pod"
	msg := sprintf("Pod %v could not be created because it uses images that are tagged latest or images with no tags",[input.request.object.metadata.name])
}

ensure {
	# Does the image tag is latest? this should violate the policy
	has_string(":latest",requested_images)
}
ensure {
	# OR Is this a naked image? this should also violate the policy
	not has_string(":",requested_images)

}
has_string(str,arr){
	contains(arr[_],str)
}
