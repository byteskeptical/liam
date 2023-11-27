# Lambda Invoked Automated Mailer

## Overview

Another SES Lambda function to help you clutter someone elses inbox but do so utilizing the latest in AWS security. Of course liam is using the V2 encryption client but were it differs is actually using the ephemeral keys in the V2 call headers to decrypt your mails just before forwarding. Maximizing security while minimizing API calls, saving you on everything, your welcome.

## Configuration

Modify the `DEFAULT_CONFIG` as needed for your environment:

```ruby
DEFAULT_CONFIG = {
  allow_plus_sign: true,
  email_bucket: 'your-email-bucket-name',
  email_key_prefix: 'email-prefix/',
  from_email: 'noreply@yourdomain.com',
  forward_mapping: {
    'info@yourdomain.com' => ['contact@anotherdomain.com'],
    '@yourdomain.com' => ['default@anotherdomain.com']
  },
  headers: ['Message-ID', 'Date', 'Subject'],
  kms: 'your-kms-key-id',
  region: 'us-east-1',
  subject_prefix: '[Forwarded]',
  tags: [{name: 'Project', value: 'Redacted'}]
}
```

### Parameters:
    `allow_plus_sign` - To filter out or not filter out '+alias' syntax in email addresses before mapping, that is the question.
    `email_bucket` - S3 bucket name where incoming emails are stored.
    `email_key_prefix` - Object key prefix for stored emails in S3.
    `from_email` - Default 'From' email address for forwarded emails.
    `forward_mapping` - A hash mapping of domain or domain addresses to forwarded recipient addresses.
    `headers` - Array of email headers that should be preserved during forwarding.
    `kms` - Key Management Service (KMS) key ID for email encryption.
    `region` - The AWS region your S3 and SES services are located in.
    `subject_prefix` - A string prefix you feel is important enough to prepend to all forwarded email subjects.
    `tags` - don't make me explain tags to you.

## Installation

Ensure AWS CLI is configured with appropriate permissions. (optional)
Create required S3 bucket and SES setup.
Package and deploy the Lambda function through AWS CLI or AWS Management Console.
Configure triggers to invoke the Lambda function on incoming email events.

## Usage

Requires an SES `event` payload and fields like mail and receipt:

1. Incoming SES event triggers liam.
2. Liam fetches encrypted blob you call mail from the specified S3 bucket.
3. Mail headers are processed and recipients are mapped based on configuration.
4. Altered mail is forwarded to new recipients via SES.

## Error Handling

Error handling in the code logs issues and halts processing when errors occur. It is advisable to set up Dead Letter Queues (DLQs) to capture failed processing attempts for further investigation.

## Logging

Logging is carried out via AWS CloudWatch, with detailed logs for each step of the processing. Make sure to check CloudWatch logs for debugging errors or to track the function execution history.

## Security

The function uses `Aws::S3::EncryptionV2::Client` with AES-GCM encryption and KMS for key management to securely handle your emails.

## Contributions

For suggestions, improvements, or contributions, please open a pull request or issue.
