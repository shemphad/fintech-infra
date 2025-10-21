provider "aws" {
  region = "us-east-2"
}

resource "aws_acm_certificate" "shemphadglobalconcept_cert" {
  domain_name               = var.domain_name
  subject_alternative_names = var.san_domains
  validation_method         = "DNS"
  tags                      = var.tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.shemphadglobalconcept_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # allow Terraform to UPSERT the record if it already exists
  allow_overwrite = true
}


resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.shemphadglobalconcept_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}