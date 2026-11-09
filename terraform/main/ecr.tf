resource "aws_ecr_repository" "dbt" {
  name                 = "ecom-dbt"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# keep only the 5 most recent images so old builds don't pile up
resource "aws_ecr_lifecycle_policy" "dbt" {
  repository = aws_ecr_repository.dbt.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}