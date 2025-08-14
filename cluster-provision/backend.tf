terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "k8s-cluster/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
