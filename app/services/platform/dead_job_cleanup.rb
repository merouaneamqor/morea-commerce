# frozen_string_literal: true

module Platform
  # Removes Sidekiq dead-set entries that can never run again (missing classes)
  # or clears the whole dead set after an explicit platform confirmation.
  class DeadJobCleanup
    Result = Struct.new(:removed, :mode, keyword_init: true)

    def self.orphan_class?(class_name)
      constant_name = class_name.to_s.split("#", 2).first.to_s
      return true if constant_name.blank?

      constant_name.safe_constantize.nil?
    end

    def self.clear_orphans!
      require "sidekiq/api"
      removed = 0
      Sidekiq::DeadSet.new.each do |job|
        next unless orphan_class?(job.display_class)

        job.delete
        removed += 1
      end
      Result.new(removed: removed, mode: "orphans")
    end

    def self.clear_all!
      require "sidekiq/api"
      set = Sidekiq::DeadSet.new
      removed = set.size
      set.clear
      Result.new(removed: removed, mode: "all")
    end

    def self.delete!(jid:)
      require "sidekiq/api"
      job = Sidekiq::DeadSet.new.find_job(jid.to_s)
      return Result.new(removed: 0, mode: "jid") unless job

      job.delete
      Result.new(removed: 1, mode: "jid")
    end
  end
end
