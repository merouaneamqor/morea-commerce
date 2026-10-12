# frozen_string_literal: true

# Smoke check for catalog autonomy services.
# Usage: bin/rails runner script/autonomy_smoke.rb [store_slug]

slug = ARGV[0].presence || ENV.fetch("DEFAULT_STORE_SLUG", "morea")
store = Store.find_by!(slug: slug)

puts "Store: #{store.name} (#{store.slug})"
puts "Profile languages: #{Catalog::Autonomy.profile_for(store)['languages'].inspect}"
puts "Schema fields: #{Catalog::Autonomy.product_schema['fields'].size}"

audit = Catalog::Audit.store(store, limit: 100)
puts "Audit issues: #{audit[:summary][:issue_count]} (auto-fixable #{audit[:summary][:auto_fixable_count]})"

suggestions = Catalog::SuggestCollections.call(store, limit: 10)
puts "Collection suggestions: #{suggestions[:suggestions].size}"

ops = [
  {
    "type" => "update_store_profile",
    "attrs" => { "tone" => "Warm and precise", "targetAudience" => "Moroccan modest fashion shoppers" }
  }
]
preview = Catalog::Changesets.preview(store, operations: ops, summary: "Smoke profile update")
puts "Preview token: #{preview[:token]} maxLevel=#{preview[:max_level]}"

applied = Catalog::Changesets.apply(store, token: preview[:token])
puts "Applied status: #{applied[:status]}"

verified = Catalog::Changesets.verify(store, token: preview[:token])
puts "Verified ok: #{verified[:verification]['ok']}"

rolled = Catalog::Changesets.rollback(store, token: preview[:token])
puts "Rollback status: #{rolled[:status]}"
puts "OK"
