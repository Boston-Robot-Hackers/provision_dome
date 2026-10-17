# A minimal public network: one VCN, one public subnet reachable from the
# internet, and a security list that admits inbound SSH always, plus the single
# noVNC port 48210 when var.vnc_access = "public" (F14). Foxglove and the
# tunnel-mode desktop are reached over `ssh -L`, so no other port is opened.

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

  # Public noVNC port, opened only in public VNC-access mode
  # (var.vnc_access = "public"): one port, 48210, a controllable desktop behind
  # a VNC password. tunnel/none keep the box SSH-only. `make vnc-up`/`vnc-down`
  # flip this as a manual override. See feature F14.
  # The source is var.vnc_allowed_cidr, not 0.0.0.0/0 (F15.5): `make vnc-up`
  # passes the caller's own address, so the internet is not on this port even
  # while the desktop is up.
  dynamic "ingress_security_rules" {
    for_each = var.vnc_access == "public" ? toset([48210]) : toset([])
    content {
      protocol = "6" # TCP
      source   = var.vnc_allowed_cidr
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
