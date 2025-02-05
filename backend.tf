# Backend configuration
terraform {
  backend "s3" {
    bucket         = "my-tf-state-bucket2122"
    key            = "path/terraform.tfstate"
    region         = "us-east-1"
  }
}
