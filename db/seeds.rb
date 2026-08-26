# Bootstraps the first admin, so a fresh deploy has someone who can reach
# /admin. Every later admin is promoted from the Users page.
#
# The password is (re)set on every run on purpose: seeding an address that
# already has an account must not hand that account admin while leaving its
# existing password in place.
email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
password = ENV.fetch("ADMIN_PASSWORD") { Rails.env.production? ? SecureRandom.alphanumeric(24) : "password" }

user = User.find_or_initialize_by(email: email)
user.password = password
user.role = "admin"
user.save!

puts "Admin: #{email} / #{password}"
