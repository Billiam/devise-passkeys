require 'devise/strategies/authenticatable'
require_relative 'passkey_issuer'

module Devise
  module Strategies
    class PasskeyAuthenticatable < Authenticatable
      include Warden::WebAuthn::StrategyHelpers

      def store?
        super && !mapping.to.skip_session_storage.include?(:passkey_auth)
      end

      def valid?
        return true unless parsed_credential.nil?

        fail(:credential_missing_or_could_not_be_parsed)
        false
      end

      def authenticate!
        passkey = verify_authentication_and_find_stored_credential

        return if passkey.nil?

        resource = mapping.to.find_for_passkey(passkey)

        return fail(:invalid_passkey) unless resource

        if validate(resource)
          remember_me(resource)
          resource.after_passkey_authentication
          record_passkey_use(passkey: passkey)
          update_sign_count(passkey: passkey, webauthn_credential: webauthn_credential)
          success!(resource)
          return
        end

        # In paranoid mode, fail with a generic invalid error
        Devise.paranoid ? fail(:invalid_passkey) : fail(:not_found_in_database)
      end

      def credential_finder
        Devise::Passkeys::PasskeyIssuer::CredentialFinder.new(resource_class: mapping.to)
      end

      def record_passkey_use(passkey:)
        passkey.update_attribute(:last_used_at, Time.current)
      end

      def update_sign_count(passkey:, webauthn_credential:)
        passkey.update_attribute(:sign_count, webauthn_credential.sign_count)
      end
    end
  end
end

Warden::Strategies.add(:passkey_authenticatable, Devise::Strategies::PasskeyAuthenticatable)