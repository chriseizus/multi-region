bucket         = "rh-tf-state-sandbox"
key            = "global/bootstrap/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "tf-state-locks"
encrypt        = true
