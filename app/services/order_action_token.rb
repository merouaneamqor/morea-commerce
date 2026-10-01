# frozen_string_literal: true

require "jwt"

class OrderActionToken
  ALGORITHM = "HS256"
  DEFAULT_TTL = 7.days

  class InvalidToken < StandardError; end

  def self.issue(order:, action:, ttl: DEFAULT_TTL)
    new.issue(order: order, action: action, ttl: ttl)
  end

  def self.verify!(token, expected_action: nil, expected_order_id: nil)
    new.verify!(token, expected_action: expected_action, expected_order_id: expected_order_id)
  end

  def issue(order:, action:, ttl: DEFAULT_TTL)
    action = action.to_s
    raise ArgumentError, "Unsupported action #{action}" unless %w[confirm cancel].include?(action)

    payload = {
      "order_id" => order.id,
      "order_number" => order.number,
      "action" => action,
      "exp" => ttl.from_now.to_i,
      "iat" => Time.current.to_i
    }

    JWT.encode(payload, secret, ALGORITHM)
  end

  def verify!(token, expected_action: nil, expected_order_id: nil)
    raise InvalidToken, "Missing token" if token.blank?

    payload, = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
    payload = payload.stringify_keys

    if expected_action.present? && payload["action"] != expected_action.to_s
      raise InvalidToken, "Token action mismatch"
    end

    if expected_order_id.present? && payload["order_id"].to_i != expected_order_id.to_i
      raise InvalidToken, "Token order mismatch"
    end

    payload
  rescue JWT::ExpiredSignature
    raise InvalidToken, "Token expired"
  rescue JWT::DecodeError => e
    raise InvalidToken, e.message
  end

  private

  def secret
    ENV["ORDERS_JWT_SECRET"].presence || Rails.application.secret_key_base
  end
end
