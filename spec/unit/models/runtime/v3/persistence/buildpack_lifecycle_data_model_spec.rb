require 'spec_helper'

module VCAP::CloudController
  RSpec.describe BuildpackLifecycleDataModel do
    subject(:lifecycle_data) { BuildpackLifecycleDataModel.new }

    it_behaves_like 'a model with an encrypted attribute' do
      let(:value_to_encrypt) { 'https://acme-buildpack.com' }
      let(:encrypted_attr) { :buildpack_url }
      let(:storage_column) { :encrypted_buildpack_url }
      let(:attr_salt) { :encrypted_buildpack_url_salt }
    end

    describe '#stack' do
      it 'persists the stack' do
        lifecycle_data.stack = 'cflinuxfs2'
        lifecycle_data.save
        expect(lifecycle_data.reload.stack).to eq 'cflinuxfs2'
      end
    end

    describe '#buildpack' do
      context 'url' do
        it 'persists the buildpack' do
          lifecycle_data.buildpack = 'http://buildpack.example.com'
          lifecycle_data.save
          expect(lifecycle_data.reload.buildpack).to eq 'http://buildpack.example.com'
          expect(lifecycle_data.reload.buildpack_url).to eq 'http://buildpack.example.com'
        end
      end

      context 'admin buildpack name' do
        let(:buildpack) { Buildpack.make(name: 'ruby') }

        it 'persists the buildpack' do
          lifecycle_data.buildpack = 'ruby'
          lifecycle_data.save
          expect(lifecycle_data.reload.buildpack).to eq 'ruby'
          expect(lifecycle_data.reload.admin_buildpack_name).to eq 'ruby'
        end
      end
    end

    describe '#buildpack_model' do
      let!(:admin_buildpack) { Buildpack.make(name: 'bob') }

      context 'when the buildpack is nil' do
        subject(:lifecycle_data) { BuildpackLifecycleDataModel.new(buildpack: nil) }

        it 'is AutoDetectionBuildpack' do
          expect(lifecycle_data.buildpack_model).to be_an(AutoDetectionBuildpack)
        end
      end

      context 'when the buildpack is an admin buildpack' do
        subject(:lifecycle_data) { BuildpackLifecycleDataModel.new(buildpack: admin_buildpack.name) }

        it 'is the matching admin buildpack' do
          expect(lifecycle_data.buildpack_model).to eq(admin_buildpack)
        end
      end

      context 'when the buildpack is a custom buildpack (url)' do
        let(:custom_buildpack_url) { 'https://github.com/buildpacks/the-best' }
        subject(:lifecycle_data) { BuildpackLifecycleDataModel.new(buildpack: custom_buildpack_url) }

        it 'is a custom buildpack for the URL' do
          buildpack_model = lifecycle_data.buildpack_model
          expect(buildpack_model).to be_a(CustomBuildpack)
          expect(buildpack_model.url).to eq(custom_buildpack_url)
        end
      end
    end

    describe '#using_custom_buildpack?' do
      context 'when using a custom buildpack' do
        subject(:lifecycle_data) { BuildpackLifecycleDataModel.new(buildpack: 'https://github.com/buildpacks/the-best') }

        it 'returns true' do
          expect(lifecycle_data.using_custom_buildpack?).to eq true
        end
      end

      context 'when not using a custom buildpack' do
        subject(:lifecycle_data) { BuildpackLifecycleDataModel.new(buildpack: nil) }

        it 'returns false' do
          expect(lifecycle_data.using_custom_buildpack?).to eq false
        end
      end
    end

    describe '#to_hash' do
      let(:expected_lifecycle_data) do
        { buildpacks: [buildpack], stack: 'cflinuxfs2' }
      end
      let(:buildpack) { 'ruby' }
      let(:stack) { 'cflinuxfs2' }

      before do
        lifecycle_data.stack = stack
        lifecycle_data.buildpack = buildpack
        lifecycle_data.save
      end

      it 'returns the lifecycle data as a hash' do
        expect(lifecycle_data.to_hash).to eq expected_lifecycle_data
      end

      context 'when the user has not specified a buildpack' do
        let(:buildpack) { nil }
        let(:expected_lifecycle_data) do
          { buildpacks: [], stack: 'cflinuxfs2' }
        end

        it 'returns the lifecycle data as a hash' do
          expect(lifecycle_data.to_hash).to eq expected_lifecycle_data
        end
      end

      context 'when the buildpack is an url' do
        let(:buildpack) { 'https://github.com/puppychutes' }

        it 'returns the lifecycle data as a hash' do
          expect(lifecycle_data.to_hash).to eq expected_lifecycle_data
        end

        it 'calls out to UrlSecretObfuscator' do
          allow(CloudController::UrlSecretObfuscator).to receive(:obfuscate)

          lifecycle_data.to_hash

          expect(CloudController::UrlSecretObfuscator).to have_received(:obfuscate).exactly :once
        end
      end

      context 'when there are multiple buildpacks' do
        let(:buildpack2) { 'python' }
        let(:expected_lifecycle_data) do
          { buildpacks: [buildpack, buildpack2], stack: 'cflinuxfs2' }
        end

        it 'returns the lifecycle data as a hash' do
          lifecycle_data.buildpacks = [buildpack, buildpack2]
          lifecycle_data.save

          expect(lifecycle_data.to_hash).to eq expected_lifecycle_data
        end
      end
    end

    describe 'associations' do
      it 'can be associated with a droplet' do
        droplet = DropletModel.make
        lifecycle_data.droplet = droplet
        lifecycle_data.save
        expect(lifecycle_data.reload.droplet).to eq(droplet)
      end

      it 'can be associated with apps' do
        app = AppModel.make
        lifecycle_data.app = app
        lifecycle_data.save
        expect(lifecycle_data.reload.app).to eq(app)
      end

      it 'can be associated with a build' do
        build = BuildModel.make
        lifecycle_data.build = build
        lifecycle_data.save
        expect(lifecycle_data.reload.build).to eq(build)
      end

      it 'cannot be associated with both an app and a build' do
        build = BuildModel.make
        app = AppModel.make
        lifecycle_data.build = build
        lifecycle_data.app = app
        expect(lifecycle_data.valid?).to be(false)
        expect(lifecycle_data.errors.full_messages.first).to include('Must be associated with an app OR a build+droplet, but not both')
      end

      it 'cannot be associated with both an app and a droplet' do
        droplet = DropletModel.make
        app = AppModel.make
        lifecycle_data.droplet = droplet
        lifecycle_data.app = app
        expect(lifecycle_data.valid?).to be(false)
        expect(lifecycle_data.errors.full_messages.first).to include('Must be associated with an app OR a build+droplet, but not both')
      end
    end

    describe '#buildpacks' do
      context 'multiple buildpacks' do
        context 'admin buildpacks' do
          let(:buildpack) { Buildpack.make(name: 'ruby') }
          let(:buildpack2) { Buildpack.make(name: 'python') }

          it 'persists multiple buildpacks' do
            packs = [buildpack.name, buildpack2.name]
            lcd = lifecycle_data.save
            lcd.buildpacks = packs
            lcd.save

            expect(lifecycle_data.reload.buildpacks).to eq(packs)
          end
        end

        context 'custom buildpacks' do
          let(:buildpack) { 'http://example.com/buildpack1' }
          let(:buildpack2) { 'http://example.com/buildpack2' }

          it 'persists multiple buildpacks' do
            packs = [buildpack, buildpack2]
            lcd = lifecycle_data.save
            lcd.buildpacks = packs
            lcd.save

            expect(lifecycle_data.reload.buildpacks).to eq(packs)
          end
        end
      end
    end
  end
end
