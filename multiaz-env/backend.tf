terraform {
  backend "s3" {
    bucket       = "sbh-workload-demo-s3-tfstate-921810471078"
    key          = "infra/multiaz-env/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "sbh-workload"
    use_lockfile = true
  }
}
