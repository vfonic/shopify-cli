# frozen_string_literal: true

module Extension
  module Models
    module SpecificationHandlers
      class CheckoutUiExtension < Default
        L10N_FILE_SIZE_LIMIT = 16 * 1024 # 16kb
        L10N_BUNDLE_SIZE_LIMIT = 256 * 1024 # 256kb
        LOCALE_CODE_FORMAT = %r{
          \A
          (?<language>[a-z]{2,3}) # Language tag
          (?:
           -
           (?<region>[a-zA-Z0-9]+) # Optional region subtag
          )?
          \z}x
        PERMITTED_CONFIG_KEYS = [:extension_points, :metafields, :name]

        def config(context)
          {
            **Features::ArgoConfig.parse_yaml(context, PERMITTED_CONFIG_KEYS),
            **argo.config(context, include_renderer_version: false),
            **localization(context)
          }
        end

        def supplies_resource_url?
          true
        end

        def build_resource_url(context:, shop:)
          product = Tasks::GetProduct.call(context, shop)
          return unless product
          format("/cart/%<variant_id>d:%<quantity>d", variant_id: product.variant_id, quantity: 1)
        end

        private

        def localization(context)
          current_size = 0
          default_locale = nil
          Dir.chdir(context.root) do
            locale_filenames = Dir["**/*"].select { |filename| valid_l10n_file?(filename) }
            # Localization is optional
            if locale_filenames.size == 0
              return {}
            end
            
            locale_filenames.each do |filename|
              current_size += File.size(filename)
              if current_size > L10N_BUNDLE_SIZE_LIMIT
                raise Extension::Errors::BundleTooLargeError,
                      "Total size of all locale files must be less than #{CLI::Kit::Util.to_filesize(L10N_BUNDLE_SIZE_LIMIT)}"
              end
            end

            default_locale_matches = locale_filenames.grep(/default/)
            if default_locale_matches.size != 1
              raise Extension::Errors::SingleDefaultLocaleError,
                "There must be one and only one locale identified as the default locale, e.g. `en.default.json`"
            end
            default_locale = File.basename(File.basename(default_locale_matches.first, ".json"), ".default")

            locale_filenames.map do |filename|
              locale = File.basename(File.basename(filename, ".json"), ".default")
              [locale, Base64.strict_encode64(File.read(filename, mode: "rt", encoding: "UTF-8"))]
            end
              .yield_self do |encoded_files_by_locale|
              {
                "localization" => {
                  "default_locale" => default_locale,
                  "translations" => encoded_files_by_locale.to_h,
                },
              }
            end
          end
        end

        def valid_l10n_file?(filename)
          return false unless File.file?(filename)

          dirname = File.dirname(filename)
          return false unless dirname == "locales"

          ext = File.extname(filename)
          if ext != ".json"
            raise Extension::Errors::InvalidFilenameError,
              "Invalid locale filename: #{filename}; Only .json files are allowed"
          end

          basename = File.basename(File.basename(filename, ".json"), ".default")
          unless valid_locale_code?(basename)
            raise Extension::Errors::InvalidFilenameError,
              "Invalid locale filename: #{filename}; Locale code should be 2 or 3 lowercase letters, optionally followed by an alphanumeric region code, e.g. `fr-CA`"
          end

          if File.size(filename) > L10N_FILE_SIZE_LIMIT
            raise Extension::Errors::FileTooLargeError,
              "Locale file #{filename} too large; Size must be less than #{CLI::Kit::Util.to_filesize(L10N_FILE_SIZE_LIMIT)}"
          end

          true
        end

        def valid_locale_code?(locale_code)
          LOCALE_CODE_FORMAT.match?(locale_code)
        end
      end
    end
  end
end
