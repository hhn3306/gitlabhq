# frozen_string_literal: true

require 'spec_helper'

describe Admin::ApplicationSettingsController do
  include StubENV

  let(:group) { create(:group) }
  let(:project) { create(:project, namespace: group) }
  let(:admin) { create(:admin) }
  let(:user) { create(:user)}

  before do
    stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
  end

  describe 'GET #usage_data with no access' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:transaction_open?).and_return(false)
      sign_in(user)
    end

    it 'returns 404' do
      get :usage_data, format: :html

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET #usage_data' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:transaction_open?).and_return(false)
      sign_in(admin)
    end

    it 'returns HTML data' do
      get :usage_data, format: :html

      expect(response.body).to start_with('<span')
      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns JSON data' do
      get :usage_data, format: :json

      body = json_response
      expect(body["version"]).to eq(Gitlab::VERSION)
      expect(body).to include('counts')
      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe 'PUT #update' do
    before do
      sign_in(admin)
    end

    it 'updates the password_authentication_enabled_for_git setting' do
      put :update, params: { application_setting: { password_authentication_enabled_for_git: "0" } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.password_authentication_enabled_for_git).to eq(false)
    end

    it 'updates the default_project_visibility for string value' do
      put :update, params: { application_setting: { default_project_visibility: "20" } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.default_project_visibility).to eq(Gitlab::VisibilityLevel::PUBLIC)
    end

    it 'update the restricted levels for string values' do
      put :update, params: { application_setting: { restricted_visibility_levels: %w[10 20] } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.restricted_visibility_levels).to eq([10, 20])
    end

    it 'updates the restricted_visibility_levels when empty array is passed' do
      put :update, params: { application_setting: { restricted_visibility_levels: [""] } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.restricted_visibility_levels).to be_empty
    end

    it 'updates the receive_max_input_size setting' do
      put :update, params: { application_setting: { receive_max_input_size: "1024" } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.receive_max_input_size).to eq(1024)
    end

    it 'updates the default_project_creation for string value' do
      put :update, params: { application_setting: { default_project_creation: ::Gitlab::Access::MAINTAINER_PROJECT_ACCESS } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.default_project_creation).to eq(::Gitlab::Access::MAINTAINER_PROJECT_ACCESS)
    end

    it 'updates minimum_password_length setting' do
      put :update, params: { application_setting: { minimum_password_length: 10 } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.minimum_password_length).to eq(10)
    end

    it 'updates namespace_storage_size_limit setting' do
      put :update, params: { application_setting: { namespace_storage_size_limit: '100' } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(response).to set_flash[:notice].to('Application settings saved successfully')
      expect(ApplicationSetting.current.namespace_storage_size_limit).to eq(100)
    end

    it 'does not accept an invalid namespace_storage_size_limit' do
      put :update, params: { application_setting: { namespace_storage_size_limit: '-100' } }

      expect(response).to render_template(:general)
      expect(assigns(:application_setting).errors[:namespace_storage_size_limit]).to be_present
      expect(ApplicationSetting.current.namespace_storage_size_limit).not_to eq(-100)
    end

    it 'updates repository_storages_weighted setting' do
      put :update, params: { application_setting: { repository_storages_weighted_default: 75 } }

      expect(response).to redirect_to(general_admin_application_settings_path)
      expect(ApplicationSetting.current.repository_storages_weighted_default).to eq(75)
    end

    context 'external policy classification settings' do
      let(:settings) do
        {
          external_authorization_service_enabled: true,
          external_authorization_service_url: 'https://custom.service/',
          external_authorization_service_default_label: 'default',
          external_authorization_service_timeout: 3,
          external_auth_client_cert: File.read('spec/fixtures/passphrase_x509_certificate.crt'),
          external_auth_client_key: File.read('spec/fixtures/passphrase_x509_certificate_pk.key'),
          external_auth_client_key_pass: "5iveL!fe"
        }
      end

      it 'updates settings when the feature is available' do
        put :update, params: { application_setting: settings }

        settings.each do |attribute, value|
          expect(ApplicationSetting.current.public_send(attribute)).to eq(value)
        end
      end
    end

    describe 'verify panel actions' do
      before do
        stub_feature_flags(instance_level_integrations: false)
      end

      Admin::ApplicationSettingsController::VALID_SETTING_PANELS.each do |valid_action|
        it_behaves_like 'renders correct panels' do
          let(:action) { valid_action }
        end
      end
    end
  end

  describe 'PATCH #integrations' do
    before do
      stub_feature_flags(instance_level_integrations: false)
      sign_in(admin)
    end

    describe 'EKS integration' do
      let(:application_setting) { ApplicationSetting.current }
      let(:settings_params) do
        {
          eks_integration_enabled: '1',
          eks_account_id: '123456789012',
          eks_access_key_id: 'dummy access key',
          eks_secret_access_key: 'dummy secret key'
        }
      end

      it 'updates EKS settings' do
        patch :integrations, params: { application_setting: settings_params }

        expect(application_setting.eks_integration_enabled).to be_truthy
        expect(application_setting.eks_account_id).to eq '123456789012'
        expect(application_setting.eks_access_key_id).to eq 'dummy access key'
        expect(application_setting.eks_secret_access_key).to eq 'dummy secret key'
      end

      context 'secret access key is blank' do
        let(:settings_params) { { eks_secret_access_key: '' } }

        it 'does not update the secret key' do
          application_setting.update!(eks_secret_access_key: 'dummy secret key')

          patch :integrations, params: { application_setting: settings_params }

          expect(application_setting.reload.eks_secret_access_key).to eq 'dummy secret key'
        end
      end
    end
  end

  describe 'PUT #reset_registration_token' do
    before do
      sign_in(admin)
    end

    subject { put :reset_registration_token }

    it 'resets runner registration token' do
      expect { subject }.to change { ApplicationSetting.current.runners_registration_token }
    end

    it 'redirects the user to admin runners page' do
      subject

      expect(response).to redirect_to(admin_runners_path)
    end
  end

  describe 'GET #lets_encrypt_terms_of_service' do
    include LetsEncryptHelpers

    before do
      sign_in(admin)

      stub_lets_encrypt_client
    end

    subject { get :lets_encrypt_terms_of_service }

    it 'redirects the user to the terms of service page' do
      subject

      expect(response).to redirect_to("https://letsencrypt.org/documents/LE-SA-v1.2-November-15-2017.pdf")
    end
  end
end
