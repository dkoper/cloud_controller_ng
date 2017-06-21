require 'cloud_controller/diego/lifecycles/lifecycles'
require 'utils/uri_utils'

module VCAP::CloudController
  class BuildpackLifecycleDataModel < Sequel::Model(:buildpack_lifecycle_data)
    LIFECYCLE_TYPE = Lifecycles::BUILDPACK

    encrypt :buildpack_url, salt: :encrypted_buildpack_url_salt, column: :encrypted_buildpack_url

    many_to_one :droplet,
      class:                   '::VCAP::CloudController::DropletModel',
      key:                     :droplet_guid,
      primary_key:             :guid,
      without_guid_generation: true

    many_to_one :build,
      class:                   '::VCAP::CloudController::BuildModel',
      key:                     :build_guid,
      primary_key:             :guid,
      without_guid_generation: true

    many_to_one :app,
      class:                   '::VCAP::CloudController::AppModel',
      key:                     :app_guid,
      primary_key:             :guid,
      without_guid_generation: true

    def buildpack=(buildpack)
      self.buildpack_url        = nil
      self.admin_buildpack_name = nil

      if UriUtils.is_uri?(buildpack)
        self.buildpack_url = buildpack
      else
        self.admin_buildpack_name = buildpack
      end
    end

    def buildpack
      return self.admin_buildpack_name if self.admin_buildpack_name.present?
      self.buildpack_url
    end

    def buildpacks
      packs = VCAP::CloudController::LifecycleBuildpack.where(buildpack_lifecycle_data_guid: self.guid).all
      packs.map(&:admin_buildpack_name)
    end

    def buildpacks=(buildpacks)
      buildpacks.each_with_index do |buildpack_name, index|
        VCAP::CloudController::LifecycleBuildpack.create(
          buildpack_lifecycle_data_guid: self.guid,
          admin_buildpack_name: buildpack_name,
          position: index
        )
      end
    end

    def buildpack_model
      return AutoDetectionBuildpack.new if buildpack.nil?

      known_buildpack = Buildpack.find(name: buildpack)
      return known_buildpack if known_buildpack

      CustomBuildpack.new(buildpack)
    end

    def using_custom_buildpack?
      buildpack_model.custom?
    end

    def to_hash
      { buildpacks: buildpacks ? buildpacks.map{|pack| CloudController::UrlSecretObfuscator.obfuscate(pack)} : [], stack: stack }
    end

    def validate
      if app && (build || droplet)
        errors.add(:lifecycle_data, 'Must be associated with an app OR a build+droplet, but not both')
      end
    end
  end

  class LifecycleBuildpack < Sequel::Model(:lifecycle_buildpacks)
    many_to_one :buildpack_lifecycle_data,
      class:                   '::VCAP::CloudController::BuildpackLifecycleDataModel',
      key:                     :buildpack_lifecycle_data_guid,
      primary_key:             :guid,
      without_guid_generation: true
  end
end


