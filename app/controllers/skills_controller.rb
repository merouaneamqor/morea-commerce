# frozen_string_literal: true

class SkillsController < ActionController::API
  SKILL_NAME = "morea-catalog"
  DISCOVERY_SCHEMA = "https://schemas.agentskills.io/discovery/0.2.0/schema.json"

  before_action :skill_headers

  def index
    render json: {
      "$schema": DISCOVERY_SCHEMA,
      skills: [
        {
          name: SKILL_NAME,
          type: "skill-md",
          description: skill_description,
          url: skill_url("/.well-known/agent-skills"),
          digest: skill_digest
        }
      ]
    }
  end

  def legacy_index
    render json: {
      skills: [
        {
          name: SKILL_NAME,
          description: skill_description,
          files: [ "SKILL.md" ]
        }
      ]
    }
  end

  def show
    send_data skill_bytes, type: "text/markdown; charset=utf-8", disposition: "inline"
  end

  private

  def skill_headers
    response.set_header("Cache-Control", "public, max-age=300")
    response.set_header("Access-Control-Allow-Origin", "*")
  end

  def skill_url(base_path)
    "#{request.base_url}#{base_path}/#{SKILL_NAME}/SKILL.md"
  end

  def skill_digest
    "sha256:#{Digest::SHA256.hexdigest(skill_bytes)}"
  end

  def skill_description
    metadata.fetch("description")
  end

  def metadata
    match = skill_text.match(/\A---\r?\n(.*?)\r?\n---\r?\n/m)
    YAML.safe_load(match[1])
  end

  def skill_text
    skill_bytes.dup.force_encoding(Encoding::UTF_8)
  end

  def skill_bytes
    File.binread(Rails.root.join(".agents/skills/#{SKILL_NAME}/SKILL.md"))
  end
end
