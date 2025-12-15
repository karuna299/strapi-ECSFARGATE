terraform {
  backend "s3" {
    bucket       = "my-terraform-state-6"
    key          = "terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
  }
}
