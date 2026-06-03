terraform {
  backend "s3" {
    bucket                      = "terraform-state"
    key                         = "oci-3tier/terraform.tfstate"
    region                      = "ap-sydney-1"
    endpoints = {
        s3 = "https://sdlvq8nmuuve.compat.objectstorage.ap-sydney-1.oraclecloud.com"
        }
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
  }
}