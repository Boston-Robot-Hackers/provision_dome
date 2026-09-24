# Newest full (non-Minimal) Canonical Ubuntu 24.04 aarch64 image compatible
# with the A1 shape. operating_system_version "24.04" is the full image; the
# Minimal variant reports "24.04 Minimal aarch64" and is not selected here.
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# A bare box: no cloud-init user-data, no pre-created DOME_USER, no swap. TF07.0
# validates the four baseline breakages by running the scripts by hand as the
# default `ubuntu` user, exactly as 02-doc/oci-howto.md describes. Terraform
# only removes the console from the create step.
resource "oci_core_instance" "dome" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.dome.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
  }
}
