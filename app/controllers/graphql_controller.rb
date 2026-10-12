# frozen_string_literal: true

class GraphqlController < ActionController::API
  include Api::TokenAuthenticatable

  def execute
    query = params[:query]
    if query.blank?
      render json: { errors: [ { message: "Query missing" } ] }, status: :bad_request
      return
    end

    result = MoreaSchema.execute(
      query,
      variables: prepare_variables(params[:variables]),
      context: { store: current_api_store },
      operation_name: params[:operationName]
    )
    render json: result
  rescue StandardError => error
    raise error unless Rails.env.local?

    render json: { errors: [ { message: error.message } ] }, status: :internal_server_error
  end

  private

  def prepare_variables(variables)
    case variables
    when String
      variables.present? ? JSON.parse(variables) : {}
    when ActionController::Parameters
      variables.to_unsafe_h
    when Hash
      variables
    else
      {}
    end
  end
end
