# Tour photos for the website and the documents customers upload when they book.

resource "aws_s3_bucket" "uploads" {
  bucket        = "${var.name}-uploads"
  force_destroy = true
}

# Public access was turned on so the website could show tour photos straight from the bucket.
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "uploads_bucket" {
  statement {
    sid       = "PublicRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "uploads" {
  bucket     = aws_s3_bucket.uploads.id
  policy     = data.aws_iam_policy_document.uploads_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.uploads]
}
