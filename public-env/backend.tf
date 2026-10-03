terraform {
  backend "s3" {
    bucket       = "sbh-workload-demo-s3-tfstate-921810471078"
    key          = "infra/public-env/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "sbh-workload"
    use_lockfile = true
  }
}
