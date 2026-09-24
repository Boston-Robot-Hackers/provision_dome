# A minimal public network: one VCN, one public subnet reachable from the
# internet, and a security list that admits only inbound SSH. Foxglove and
# noVNC are reached over `ssh -L` tunnels, so no other port is ever opened.

resource "oci_core_vcn" "dome" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.instance_name}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "domevcn"
}

resource "oci_core_internet_gateway" "dome" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.dome.id
  display_name   = "${var.instance_name}-igw"
}

resource "oci_core_route_table" "dome" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.dome.id
  display_name   = "${var.instance_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.dome.id
  }
}

resource "oci_core_security_list" "dome" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.dome.id
  display_name   = "${var.instance_name}-sl"

  # Inbound: SSH only. Everything else goes over SSH tunnels.
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # TEMPORARY test ports, opened only when var.vnc_test = true (via
  # `make vnc-up`; closed again by `make vnc-down`). 48210 = passwordless
  # view-only noVNC, 48211 = password-protected control. Steady state is
  # false, so a plain `terraform apply` keeps the box SSH-only.
  dynamic "ingress_security_rules" {
    for_each = var.vnc_test ? toset([48210, 48211]) : toset([])
    content {
      protocol = "6" # TCP
      source   = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }


  # Outbound: allow all, so apt, git, and pip reach the internet.
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "dome" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.dome.id
  display_name               = "${var.instance_name}-subnet"
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.dome.id
  security_list_ids          = [oci_core_security_list.dome.id]
  dns_label                  = "domesubnet"
  prohibit_public_ip_on_vnic = false
}
