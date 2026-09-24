output "instance_public_ip" {
  description = "Public IPv4 of the instance. SSH in with: ssh ubuntu@<this>."
  value       = oci_core_instance.dome.public_ip
}

output "instance_ocid" {
  description = "Instance OCID, for stop/start: oci compute instance action --instance-id <this> --action SOFTSTOP|START."
  value       = oci_core_instance.dome.id
}

output "image_used" {
  description = "The Ubuntu image the instance was launched from."
  value       = data.oci_core_images.ubuntu.images[0].display_name
}
