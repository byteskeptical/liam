require 'aws-sdk-s3'
require 'aws-sdk-sesv2'

# Configuration
DEFAULT_CONFIG = {
  allow_plus_sign: true,
  email_bucket: 'mailroom',
  email_key_prefix: 'example.com',
  from_email: 'noreply@example.com',
  forward_mapping: {
    'accounting@example.com' => [
      'beancounter@accountingfirm.com',
      'cfo@example.com'
    ],
    'ads@example.com' => [
      'marketing@example.com',
      'legal@lawfirm.com'
    ],
    '@example.com' => [
      'webeau@example.com'
    ]
  },
  headers: ['DKIM-Signature', 'Message-ID', 'Return-Path', 'Sender'],
  kms: '',
  region: 'us-east-1',
  subject_prefix: '',
  tags: [{name: 'Project', value: 'Raven'}]
}

# Map original recipients to the desired forward destinations.
def transform_recipients(data)
  new_recipients = []
  data[:mail][:original_recipients] = data[:mail][:recipients]

  data[:mail][:recipients].each do |orig_email|
    orig_email_key = data[:config][:allow_plus_sign] ? orig_email.downcase.gsub(/\+.*?@/, '@') : orig_email.downcase

    if data[:config][:forward_mapping].key?(orig_email_key)
      new_recipients.concat(data[:config][:forward_mapping][orig_email_key])
      data[:mail][:original_recipient] = orig_email
    else
      orig_email_domain = nil
      orig_email_user = nil

      pos = orig_email_key.rindex('@')
      if pos
        orig_email_domain = orig_email_key[pos..]
        orig_email_user = orig_email_key[0...pos]
      else
        orig_email_user = orig_email_key
      end

      if orig_email_domain && data[:config][:forward_mapping].key?(orig_email_domain)
        new_recipients.concat(data[:config][:forward_mapping][orig_email_domain])
        data[:mail][:original_recipient] = orig_email
      elsif orig_email_user && data[:config][:forward_mapping].key?(orig_email_user)
        new_recipients.concat(data[:config][:forward_mapping][orig_email_user])
        data[:mail][:original_recipient] = orig_email
      elsif data[:config][:forward_mapping].key?("@")
        new_recipients.concat(data[:config][:forward_mapping]["@"])
        data[:mail][:original_recipient] = orig_email
      end
    end
  end

  if new_recipients.empty?
    puts "Finishing process. No new recipients found for original destinations: #{data[:mail][:original_recipients].join(', ')}"
  end

  data[:mail][:recipients] = new_recipients
  data
end

# Fetches the message data from S3.
def fetch_message(data)
  s3 = Aws::S3::EncryptionV2::Client.new(content_encryption_schema: :aes_gcm_no_padding,
                                         key_wrap_schema: :kms_context,
                                         kms_key_id: :kms_allow_decrypt_with_any_cmk,
                                         region: data[:config][:region],
                                         security_profile: :v2_and_legacy)
  email_key = "#{data[:config][:email_key_prefix]}#{data[:mail][:id]}"

  puts "Fetching email at s3://#{data[:config][:email_bucket]}/#{email_key}"

  begin
    response = s3.get_object(bucket: data[:config][:email_bucket], key: email_key)
    data[:mail][:data] = response.body.read
    headers, *body = data[:mail][:data].split("\r\n\r\n", 2)
    data[:mail][:body] = body
  rescue StandardError => e
    raise "Failed to load message body from S3: #{e.message}"
  end

  data
end

# Prepare message data, making updates to headers.
def process_event(data)
  records = data[:event]['Records']
  return if records.empty?

  ses = records.first['ses']
  mail = ses['mail']
  common = mail['commonHeaders']
  forward_headers = []
  headers = mail['headers']
  headers_to_remove = data[:config][:headers]
  id = mail['messageId']
  from = common['from'].first

  if from.match(/<[^>]+>/)
      from = from.gsub(/<[^>]+>/, "<#{data[:config][:from_email]}>")
  else
      from = from.gsub(/[^<>,]+/, data[:config][:from_email])
  end

  recipients = ses['receipt']['recipients']
  reply = common['replyTo']
  subject = common['subject']
  
  if data[:config][:subject_prefix]
      subject = "#{data[:config][:subject_prefix]}#{subject}"
  end

  headers.each do |header|
      if header['name'] == 'Prefix'
          data[:config][:email_key_prefix] = "#{header['value']}/"
      elsif header['name'] == 'Subject'
          forward_headers << "#{header['name']}: #{subject}"
      elsif !headers_to_remove.include?(header['name'])
          forward_headers << "#{header['name']}: #{header['value']}"
    end
  end

  dkim = ses['receipt']['dkimVerdict']['status']
  dmarc = ses['receipt']['dmarcVerdict']['status']
  spf = ses['receipt']['spfVerdict']['status']
  spam = ses['receipt']['spamVerdict']['status']
  virus = ses['receipt']['virusVerdict']['status']

  data[:mail] = {
    dkim: dkim,
    dmarc: dmarc,
    headers: forward_headers,
    id: id,
    recipients: recipients,
    reply: reply,
    sender: from,
    spam: spam,
    spf: spf,
    subject: subject,
    virus: virus
  }

  data
end

# Forward email as a raw message for attachment support
def send_message(data)
  ses = Aws::SESV2::Client.new(region: data[:config][:region])

  response = ses.send_email({
    content: {
      raw: {
        data: data[:mail][:headers].join("\r\n") + "\r\n\r\n" + data[:mail][:body].first
      }
    },
    destination: {
      to_addresses: data[:mail][:recipients]
    },
    email_tags: data[:config][:tags],
    from_email_address: data[:mail][:sender],
    reply_to_addresses: data[:mail][:reply]
  })

  puts "Email sent from #{data[:mail][:sender]} to #{data[:mail][:recipients].join(', ')} with message ID: #{response.message_id}"
  data
end

# Lambda entry point
def handler(event:, context:)
  begin
    data = {
      event: event,
      context: context,
      config: DEFAULT_CONFIG
    }
    
    data = process_event(data)
    data = transform_recipients(data)
    data = fetch_message(data)
    data = send_message(data)

    puts 'Process finished successfully.'
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end
