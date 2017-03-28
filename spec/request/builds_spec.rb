require 'spec_helper'

RSpec.describe 'Builds' do
  let(:space) { VCAP::CloudController::Space.make }
  let(:developer) { make_developer_for_space(space) }
  let(:developer_headers) { headers_for(developer, user_name: user_name) }
  let(:user_name) { 'bob the builder' }
  let(:parsed_response) { MultiJson.load(last_response.body) }
  let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid, name: 'my-app') }

  describe 'POST /v3/builds' do
    let(:package) do
      VCAP::CloudController::PackageModel.make(
        app_guid: app_model.guid,
        state: VCAP::CloudController::PackageModel::READY_STATE,
        type: VCAP::CloudController::PackageModel::BITS_TYPE,
      )
    end
    let(:diego_staging_response) do
      {
        execution_metadata: 'String',
        detected_start_command: {},
        lifecycle_data: {
          buildpack_key: 'String',
          detected_buildpack: 'String',
        }
      }
    end
    let(:create_request) do
      {
        lifecycle: {
          type: 'buildpack',
          data: {
            buildpacks: ['http://github.com/myorg/awesome-buildpack'],
            stack: 'cflinuxfs2'
          },
        },
        package: {
          guid: package.guid
        }
      }
    end

    before do
      stack = (VCAP::CloudController::Stack.find(name: create_request[:lifecycle][:data][:stack]) ||
               VCAP::CloudController::Stack.make(name: create_request[:lifecycle][:data][:stack]))
      # putting stack in the App.make call leads to an "App doesn't have a primary key" error
      # message from sequel.
      process = VCAP::CloudController::App.make(app: app_model, memory: 1024, disk_quota: 1536)
      process.stack = stack
      process.save
      allow_any_instance_of(VCAP::CloudController::Dea::Stager).to receive(:stage)
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:v3_app_buildpack_cache_download_url).and_return('some-string')
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:v3_app_buildpack_cache_upload_url).and_return('some-string')
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:package_download_url).and_return('some-string')
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:package_droplet_upload_url).and_return('some-string')
      stub_request(:put, %r{#{TestConfig.config[:diego][:stager_url]}/v1/staging/}).
        to_return(status: 202, body: diego_staging_response.to_json)
    end

    it 'creates a Builds resource' do
      post '/v3/builds', create_request.to_json, json_headers(developer_headers)

      created_build = VCAP::CloudController::BuildModel.last

      expected_response =
        {
          'guid' => created_build.guid,
          'created_at' => iso8601,
          'updated_at' => iso8601,
          'state' => 'STAGING',
          'error' => nil,
          'lifecycle' => {
            'type' => 'buildpack',
            'data' => {
              'buildpacks' => ['http://github.com/myorg/awesome-buildpack'],
              'stack' => 'cflinuxfs2'
            },
          },
          'package' => {
            'guid' => package.guid
          },
          'droplet' => nil,
          'links' => {
            'self' => {
              'href' => "#{link_prefix}/v3/builds/#{created_build.guid}"
            },
            'app' => {
              'href' => "#{link_prefix}/v3/apps/#{package.app.guid}"
            }
          }
        }

      expect(last_response.status).to eq(201), last_response.body
      expect(parsed_response).to be_a_response_like(expected_response)

      event = VCAP::CloudController::Event.last
      expect(event.values).to include(
        type:              'audit.app.droplet.create',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my-app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid,
      )
    end
  end

  describe 'GET /v3/builds' do
    let(:build) { VCAP::CloudController::BuildModel.make(package: package) }
    let(:package) { VCAP::CloudController::PackageModel.make(app_guid: app_model.guid) }
    let(:droplet) { VCAP::CloudController::DropletModel.make(
      state: VCAP::CloudController::DropletModel::STAGED_STATE,
      package_guid: package.guid,
      build: build,
    )
    }

    before do
      droplet.buildpack_lifecycle_data.update(buildpack: 'http://github.com/myorg/awesome-buildpack', stack: 'cflinuxfs2')
    end
    it 'shows the build' do
      get "v3/builds/#{build.guid}", nil, json_headers(developer_headers)

      parsed_response = MultiJson.load(last_response.body)

      expected_response =
        {
          'guid' => build.guid,
          'created_at' => iso8601,
          'updated_at' => iso8601,
          'state' => 'STAGED',
          'error' => nil,
          'lifecycle' => {
            'type' => 'buildpack',
            'data' => {
              'buildpacks' => ['http://github.com/myorg/awesome-buildpack'],
              'stack' => 'cflinuxfs2'
            },
          },
          'package' => {
            'guid' => package.guid
          },
          'droplet' => {
            'guid' => droplet.guid
          },
          'links' => {
            'self' => {
              'href' => "#{link_prefix}/v3/builds/#{build.guid}"
            },
            'app' => {
              'href' => "#{link_prefix}/v3/apps/#{package.app.guid}"
            }
          }
        }

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end
  end
end