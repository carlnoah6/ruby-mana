# frozen_string_literal: true

# Example: Data cleaning — LLM normalizes messy real-world data
require "mana"

raw_contacts = [
  { name: "john doe", phone: "1234567890", email: "JOHN@GMAIL.COM" },
  { name: "Jane Smith PhD", phone: "(555) 123-4567", email: "jane.smith@company.co" },
  { name: "bob", phone: "+1-999-888-7777", email: "BOB123@yahoo" },
  { name: "María García-López", phone: "N/A", email: "maria@empresa.mx" },
  { name: "李明", phone: "13800138000", email: "liming@163.com" }
]

cleaned = []

raw_contacts.each do |contact|
  ~"清洗这条联系人数据 #{contact.inspect}：
    - name 标准化为 Title Case（保留非拉丁字符原样）
    - phone 统一为 +X-XXX-XXX-XXXX 格式（无效的设为 nil）
    - email 小写化，无效的设为 nil
    结果存 <clean_name> <clean_phone> <clean_email>"

  cleaned << { name: clean_name, phone: clean_phone, email: clean_email }
end

cleaned.each do |c|
  puts "#{c[:name].to_s.ljust(25)} #{(c[:phone] || 'N/A').ljust(18)} #{c[:email] || 'N/A'}"
end
