require 'messages/app_route_mappings_create_message'

class AppsRouteMappingsController < ApplicationController
  include AppSubresource

  def create
    message = AppRouteMappingsCreateMessage.create_from_http_request(params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    app_guid = params['guid']
    process_type = message.process_type || 'web'

    app, route, process, space, org = AddRouteFetcher.new.fetch(
      app_guid,
      message.route_guid,
      process_type
    )

    app_not_found! unless app && can_read?(space.guid, org.guid)
    route_not_found! unless route
    process_not_found!(process_type) unless !process.nil?
    app_route_space_mismatch! unless route.space_guid == app.space_guid
    route_mapping_already_exists(process, route)
    unauthorized! unless can_write?(space.guid)

    begin
      AddRouteToApp.new(current_user, current_user_email).add(app, route, process)
    rescue AddRouteToApp::InvalidRouteMapping => e
      unprocessable!(e.message)
    end

    render status: :created, json: {}
  end

  def route_mapping_already_exists(process, requested_route)
    process.routes.each do |r|
      raise VCAP::Errors::ApiError.new_from_details('RouteMappingAlreadyExists') if r.guid == requested_route.guid
    end
  end

  def app_route_space_mismatch!
    raise VCAP::Errors::ApiError.new_from_details('RouteNotInSameSpaceAsApp')
  end

  def process_not_found!(process_type)
    raise VCAP::Errors::ApiError.new_from_details('ProcessNotFound', process_type)
  end

  def route_not_found!
    resource_not_found!(:route)
  end

  def can_write?(space_guid)
    roles.admin? || membership.has_any_roles?([Membership::SPACE_DEVELOPER], space_guid)
  end

  # alias_method :can_delete?, :can_write?
end
