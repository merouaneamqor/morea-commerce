# frozen_string_literal: true

class CatalogGuide
  PATH = Rails.root.join(".agents/skills/morea-catalog/SKILL.md")

  def self.text
    File.read(PATH).sub(/\A---\r?\n.*?\r?\n---\r?\n/m, "")
  end
end
