#create vcn
resource "oci_core_vcn" "main_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "main-vcn-github"
  dns_label      = "mainvcn"
}

#create internrt gateway
resource "oci_core_internet_gateway" "main_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "main-igw-github"
  enabled        = true
}

#create public route table
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "public-rt-github"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main_igw.id
  }
}

# ADDING PUBLIC-SECURITYLIST AND THEIR INGRESS AND EGRESS RULES
resource "oci_core_security_list" "public_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "public-security-list-tf-github"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"

    icmp_options {
      type = 3
    }
  }
  # Allow HTTP traffic to Load Balancer
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      min = 80
      max = 80
    }
  }
}

#public subnet
resource "oci_core_subnet" "public_subnet" {
  compartment_id = var.compartment_ocid

  vcn_id = oci_core_vcn.main_vcn.id

  cidr_block   = "10.0.1.0/24"
  display_name = "public-subnet-github"
  dns_label    = "publicsubnet"

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_security_list.id
  ]

  prohibit_public_ip_on_vnic = false
}

#create bastion host
#CREATE BASTION HOST
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.E5.Flex"

  sort_by    = "TIMECREATED"
  sort_order = "DESC"
}

resource "oci_core_instance" "bastion_host" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "bastion-host-tf-github"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    display_name     = "bastion-vnic"
    hostname_label   = "bastionhost"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    }
}

#CREATING NAT GATEWAY
resource "oci_core_nat_gateway" "private_nat_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "private-nat-gateway-tf-github"
}

#CREATING SERVICE GATEWAY
resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "service-gateway-tf-github"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

#CREATING PRIVATE ROUTE TABLE
resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "privateRT-tf-github"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.private_nat_gateway.id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
  }
}

#CREATE SECURITYLIST
resource "oci_core_security_list" "private_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "private-security-list-tf-github"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "1"

    icmp_options {
      type = 3
    }
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }
}

#CREATE PRIVATE SUBNET
resource "oci_core_subnet" "private_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main_vcn.id
  cidr_block                 = "10.0.2.0/24"
  display_name               = "private-subnet-tf-github"
  dns_label                  = "privatesubnet"
  prohibit_public_ip_on_vnic = true

  route_table_id = oci_core_route_table.private_rt.id

  security_list_ids = [
    oci_core_security_list.private_security_list.id
  ]
}

#CREATING APPLICATION NODE1
resource "oci_core_instance" "application_node1" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "application-node1-tf-github"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id              = oci_core_subnet.private_subnet.id
    assign_public_ip       = false
    display_name           = "application-vnic"
    hostname_label         = "appnode1"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    }
}

# CREATE AUTONOMOUS DATABASE
resource "oci_database_autonomous_database" "autonomous_db_tf" {
  compartment_id = var.compartment_ocid
  display_name = "autonomous_db_tf_gitgub"
  db_name = "MYAUTONOMOUSDBTFGITHUB"
  db_workload = "OLTP"
  admin_password = "Oracle123456"
  is_free_tier = true
}

# DOWNLOAD AUTONOMOUS DB WALLET
resource "oci_database_autonomous_database_wallet" "adb_wallet" {
  autonomous_database_id = oci_database_autonomous_database.autonomous_db_tf.id
  password = "Oracle@123456"
  base64_encode_content = true
}

# CREATE OBJECT STORAGE BUCKET
resource "oci_objectstorage_bucket" "tf_bucket" {
  compartment_id = var.compartment_ocid
  name           = "terraform-bucket-tf-github"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

#UPLOAD WALLET
resource "oci_objectstorage_object" "wallet_upload" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.tf_bucket.name
  object    = "wallet.zip"
  content   = oci_database_autonomous_database_wallet.adb_wallet.content
  depends_on = [
    oci_database_autonomous_database_wallet.adb_wallet,
    oci_objectstorage_bucket.tf_bucket
  ]
}

# GET OBJECT STORAGE NAMESPACE
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# CREATE PRE-AUTHENTICATED REQUEST (PAR)
resource "oci_objectstorage_preauthrequest" "wallet_par" {
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  bucket       = oci_objectstorage_bucket.tf_bucket.name
  name         = "wallet-par"
  access_type  = "ObjectRead"
  object_name  = "wallet.zip"
  time_expires = "2030-12-31T23:59:59Z"
}

output "wallet_par_url" {
  value = "https://objectstorage.ap-sydney-1.oraclecloud.com${oci_objectstorage_preauthrequest.wallet_par.access_uri}"
}

# CREATE LOAD BALANCER
resource "oci_load_balancer_load_balancer" "load_balancer_tf" {
  compartment_id = var.compartment_ocid
  display_name   = "load-balancer-tf-github"
  shape          = "flexible"
  is_private     = false

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }

  subnet_ids = [
    oci_core_subnet.public_subnet.id
  ]
}

# CREATE BACKEND SET
resource "oci_load_balancer_backend_set" "lb_backend_set" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf.id
  name             = "lb-backend-set-tf-github"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = 80
    url_path          = "/"
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

# ADD APPLICATION NODE1 AS BACKEND
resource "oci_load_balancer_backend" "lb_backend_node1" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf.id
  backendset_name  = oci_load_balancer_backend_set.lb_backend_set.name
  ip_address       = oci_core_instance.application_node1.private_ip
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

# CREATE HTTP LISTENER
resource "oci_load_balancer_listener" "lb_listener_http" {
  load_balancer_id         = oci_load_balancer_load_balancer.load_balancer_tf.id
  name                     = "lb-listener-http-tf"
  default_backend_set_name = oci_load_balancer_backend_set.lb_backend_set.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 60
  }
}

# OUTPUT LOAD BALANCER PUBLIC IP
output "load_balancer_public_ip" {
  value = oci_load_balancer_load_balancer.load_balancer_tf.ip_address_details[0].ip_address
}

resource "null_resource" "bastion_to_private_test" {
  triggers = {
    version = "4"
  }

  depends_on = [
    oci_core_instance.bastion_host,
    oci_core_instance.application_node1
  ]

  connection {
    type        = "ssh"
    user        = "opc"
    private_key = var.ssh_private_key
    host        = oci_core_instance.bastion_host.public_ip
  }

  # Provisioner 1: sensitive ops — output suppressed, expected
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/.ssh",
      "cat > ~/.ssh/private_key <<'EOF'\n${var.ssh_private_key}\nEOF",
      "chmod 600 ~/.ssh/private_key",
      # Connectivity test
      "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'echo CONNECTED && hostname && date' > /tmp/connectivity_result.txt 2>&1; echo $? > /tmp/connectivity_exit_code.txt",  # <-- comma was missing here
      # httpd install
      "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo yum install -y httpd 2>&1' > /tmp/httpd_install.txt 2>&1; echo $? > /tmp/httpd_install_exit.txt",
      "ssh -o StrictHostKeyChecking=no -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo systemctl enable httpd 2>&1' > /tmp/httpd_enable.txt 2>&1; echo $? > /tmp/httpd_enable_exit.txt",
      "ssh -o StrictHostKeyChecking=no -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo systemctl start httpd 2>&1' > /tmp/httpd_start.txt 2>&1; echo $? > /tmp/httpd_start_exit.txt",
      "ssh -o StrictHostKeyChecking=no -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo firewall-cmd --permanent --add-port=80/tcp 2>&1' > /tmp/httpd_fw1.txt 2>&1; echo $? > /tmp/httpd_fw1_exit.txt",
      "ssh -o StrictHostKeyChecking=no -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo firewall-cmd --reload 2>&1' > /tmp/httpd_fw2.txt 2>&1; echo $? > /tmp/httpd_fw2_exit.txt"
    ]
  }

  # Provisioner 2: no sensitive vars — fully visible in pipeline
  provisioner "remote-exec" {
    inline = [
      "echo '========================================='",
      "echo '     BASTION CONNECTIVITY TEST RESULT    '",
      "echo '========================================='",
      "echo 'Bastion hostname:'",
      "hostname",
      "echo ''",
      "echo 'Target app node IP: ${oci_core_instance.application_node1.private_ip}'",
      "echo ''",
      "echo '--- SSH Result ---'",
      "cat /tmp/connectivity_result.txt",
      "echo ''",
      "echo -n 'SSH Exit Code: '",
      "cat /tmp/connectivity_exit_code.txt",
      "echo ''",
      # removed "exit $(cat ...)" — it would kill the script before httpd results print
      "echo '========================================='",
      "echo '       HTTPD INSTALLATION RESULTS        '",
      "echo '  Target: ${oci_core_instance.application_node1.private_ip}'",
      "echo '========================================='",

      "echo ''",
      "echo '--- [1/5] yum install httpd ---'",
      "cat /tmp/httpd_install.txt",
      "echo -n 'Exit code: '; cat /tmp/httpd_install_exit.txt",

      "echo ''",
      "echo '--- [2/5] systemctl enable httpd ---'",
      "cat /tmp/httpd_enable.txt",
      "echo -n 'Exit code: '; cat /tmp/httpd_enable_exit.txt",

      "echo ''",
      "echo '--- [3/5] systemctl start httpd ---'",
      "cat /tmp/httpd_start.txt",
      "echo -n 'Exit code: '; cat /tmp/httpd_start_exit.txt",

      "echo ''",
      "echo '--- [4/5] firewall-cmd --add-port=80/tcp ---'",
      "cat /tmp/httpd_fw1.txt",
      "echo -n 'Exit code: '; cat /tmp/httpd_fw1_exit.txt",

      "echo ''",
      "echo '--- [5/5] firewall-cmd --reload ---'",
      "cat /tmp/httpd_fw2.txt",
      "echo -n 'Exit code: '; cat /tmp/httpd_fw2_exit.txt",

      "echo ''",
      "echo '========================================='",
      # Final verification
      "ssh -o StrictHostKeyChecking=no -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo systemctl is-active httpd && echo HTTPD IS RUNNING || echo HTTPD FAILED TO START'",
      # Fail apply if httpd not running
      "ssh -o StrictHostKeyChecking=no -i ~/.ssh/private_key opc@${oci_core_instance.application_node1.private_ip} 'sudo systemctl is-active --quiet httpd'",
      "echo '========================================='"
    ]
  }
}