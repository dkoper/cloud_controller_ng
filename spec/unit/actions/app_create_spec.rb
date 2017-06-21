require 'spec_helper'
require 'messages/apps/app_create_message'
require 'cloud_controller/diego/lifecycles/app_buildpack_lifecycle'

module VCAP::CloudController
  RSpec.describe AppCreate do
    let(:user_audit_info) { UserAuditInfo.new(user_email: 'gooid', user_guid: 'amelia@cats.com') }

    subject(:app_create) { AppCreate.new(user_audit_info) }

    describe '#create' do
      let(:space) { Space.make }
      let(:space_guid) { space.guid }
      let(:environment_variables) { { BAKED: 'POTATO' } }
      let(:buildpack) { Buildpack.make }
      let(:buildpack_identifier) { buildpack.name }
      let(:relationships) { { space: { data: { guid: space_guid } } } }
      let(:lifecycle_request) { { type: 'buildpack', data: { buildpacks: [buildpack_identifier], stack: 'cflinuxfs2' } } }
      let(:lifecycle) { AppBuildpackLifecycle.new(message) }
      let(:message) do
        AppCreateMessage.new(
          {
            name:                  'my-app',
            relationships:         relationships,
            environment_variables: environment_variables,
            lifecycle:             lifecycle_request
          })
      end

      context 'when the request is valid' do
        before do
          expect(message).to be_valid
          allow(lifecycle).to receive(:create_lifecycle_data_model)
        end

        it 'creates an app' do
          app = app_create.create(message, lifecycle)

          expect(app.name).to eq('my-app')
          expect(app.space).to eq(space)
          expect(app.environment_variables).to eq(environment_variables.stringify_keys)

          expect(lifecycle).to have_received(:create_lifecycle_data_model).with(app)
        end

        it 'creates an audit event' do
          expect_any_instance_of(Repositories::AppEventRepository).
            to receive(:record_app_create).with(instance_of(AppModel),
              space,
              user_audit_info,
              message.audit_hash
            )

          app_create.create(message, lifecycle)
        end
      end

      context 'when using a custom buildpack' do
        let(:buildpack_identifier) { 'https://github.com/buildpacks/my-special-buildpack' }

        context 'when custom buildpacks are disabled' do
          before do
            allow(VCAP::CloudController::Config.config).to receive(:[]).with(:disable_custom_buildpacks).and_return(true)
          end

          it 'raises an error' do
            expect {
              app_create.create(message, lifecycle)
            }.to raise_error(AppCreate::InvalidApp)
          end

          it 'does not create an app' do
            expect {
              app_create.create(message, lifecycle) rescue nil
            }.not_to change { [AppModel.count, BuildpackLifecycleDataModel.count, Event.count] }
          end
        end

        context 'when custom buildpacks are enabled' do
          before do
            allow(VCAP::CloudController::Config.config).to receive(:[]).with(:disable_custom_buildpacks).and_return(false)
          end

          it 'allows apps with custom buildpacks' do
            expect {
              app_create.create(message, lifecycle)
            }.to change(AppModel, :count).by(1)
          end
        end
      end

      it 're-raises validation errors' do
        message = AppCreateMessage.new('name' => '', relationships: relationships)
        expect {
          app_create.create(message, lifecycle)
        }.to raise_error(AppCreate::InvalidApp)
      end

      context 'when using multiple buildpacks' do
        let(:buildpack2) { Buildpack.make }
        let(:lifecycle_request) { { type: 'buildpack', data: { buildpacks: [buildpack.name, buildpack2.name], stack: 'cflinuxfs2' } } }

        it 'creates an app with multiple buildpacks' do
          app = app_create.create(message, lifecycle)
          expect(app.lifecycle_data.buildpacks).to eq([buildpack.name, buildpack2.name])
        end
      end
    end
  end
end
