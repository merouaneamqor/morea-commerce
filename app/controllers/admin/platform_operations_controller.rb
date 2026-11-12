# frozen_string_literal: true

module Admin
  # Failed Sidekiq jobs and recent connection/webhook error signals for platform ops.
  # No new tables; Redis outages render empty job lists instead of raising.
  class PlatformOperationsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    JOB_LIMIT = 25
    WEBHOOK_LIMIT = 25

    FailedJob = Struct.new(
      :jid, :class_name, :queue, :error, :failed_at, :set_name, :store_id, :store_name, :orphan,
      keyword_init: true
    )

    def index
      @redis_available = true
      @dead_jobs = []
      @retry_jobs = []
      load_sidekiq_jobs
      @orphan_count = @dead_jobs.count(&:orphan)
      @mail_status = Platform::MailStatus.current
      @webhook_failures = load_webhook_failures
    end

    def clear_orphans
      result = with_sidekiq_cleanup { Platform::DeadJobCleanup.clear_orphans! }
      return if performed?

      audit_cleanup!(result)
      redirect_to admin_platform_operations_path, notice: t("platform_admin.operations.cleared_orphans", count: result.removed)
    end

    def clear_dead
      result = with_sidekiq_cleanup { Platform::DeadJobCleanup.clear_all! }
      return if performed?

      audit_cleanup!(result)
      redirect_to admin_platform_operations_path, notice: t("platform_admin.operations.cleared_dead", count: result.removed)
    end

    def destroy_dead
      result = with_sidekiq_cleanup { Platform::DeadJobCleanup.delete!(jid: params.require(:jid)) }
      return if performed?

      audit_cleanup!(result)
      redirect_to admin_platform_operations_path, notice: t("platform_admin.operations.cleared_one")
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def with_sidekiq_cleanup
      yield
    rescue *redis_errors => error
      Rails.error.report(error, handled: true, context: { surface: "platform_operations_cleanup" })
      redirect_to admin_platform_operations_path, alert: t("platform_admin.operations.redis_unavailable")
      nil
    end

    def audit_cleanup!(result)
      Platform::AdminAudit.record(
        action: "platform.operations.clear_dead_jobs",
        actor: current_user,
        source: "ui",
        ip: request.remote_ip,
        reason: result.mode,
        count: result.removed
      )
    end

    def load_sidekiq_jobs
      require "sidekiq/api"
      @dead_jobs = read_job_set(Sidekiq::DeadSet, "dead")
      @retry_jobs = read_job_set(Sidekiq::RetrySet, "retry")
    end

    def redis_errors
      errors = [ Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, Timeout::Error ]
      errors << RedisClient::Error if defined?(RedisClient::Error)
      errors << RedisClient::CannotConnectError if defined?(RedisClient::CannotConnectError)
      errors << Redis::BaseConnectionError if defined?(Redis::BaseConnectionError)
      errors
    end

    def read_job_set(set_class, set_name)
      map_jobs(set_class.new, set_name)
    rescue *redis_errors => error
      @redis_available = false
      Rails.error.report(error, handled: true, context: { surface: "platform_operations", set: set_name })
      []
    end

    def map_jobs(set, set_name)
      entries = set.first(JOB_LIMIT).map do |job|
        store_id = extract_store_id(job.args)
        class_name = job.display_class.to_s
        FailedJob.new(
          jid: job.jid,
          class_name: class_name,
          queue: job.queue.to_s,
          error: job_error_message(job),
          failed_at: job_failed_at(job),
          set_name: set_name,
          store_id: store_id,
          store_name: nil,
          orphan: set_name == "dead" && Platform::DeadJobCleanup.orphan_class?(class_name)
        )
      end
      attach_store_names!(entries)
      entries
    end

    def job_error_message(job)
      message = job.item["error_message"].presence || job.item["error_class"].presence
      message.to_s.first(200)
    end

    def job_failed_at(job)
      stamp = job.item["failed_at"] || job.item["retry_at"]
      stamp = job.score if stamp.blank? && job.respond_to?(:score)
      return if stamp.blank?

      value = stamp.to_f
      value /= 1000.0 if value >= 1_000_000_000_000
      time = Time.zone.at(value)
      return if time.year < 2000 || time.year > 2100

      time
    rescue ArgumentError, TypeError, RangeError
      nil
    end

    def extract_store_id(value)
      case value
      when Hash
        raw = value["store_id"] || value[:store_id]
        return raw.to_i if raw.present? && raw.to_i.positive?

        value.each_value do |child|
          found = extract_store_id(child)
          return found if found
        end
        nil
      when Array
        value.each do |child|
          found = extract_store_id(child)
          return found if found
        end
        nil
      end
    end

    def attach_store_names!(entries)
      ids = entries.filter_map(&:store_id).uniq
      return if ids.empty?

      names = Store.where(id: ids).pluck(:id, :name).to_h
      entries.each { |entry| entry.store_name = names[entry.store_id] }
    end

    def load_webhook_failures
      StoreConnection.includes(:store)
        .where(
          <<~SQL.squish
            (shopify_api_error_code IS NOT NULL AND shopify_api_error_code <> '')
            OR (last_error_code IS NOT NULL AND last_error_code <> '')
          SQL
        )
        .order(updated_at: :desc)
        .limit(WEBHOOK_LIMIT)
        .to_a
    end
  end
end
