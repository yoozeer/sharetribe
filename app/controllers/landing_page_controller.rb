class LandingPageController < ActionController::Metal

  class LandingPageConfigurationError < StandardError; end
  class LandingPageContentNotFound < StandardError; end

  class Denormalizer

    def initialize(root: "composition", link_resolvers: {})
      @root = root
      @link_resolvers = link_resolvers
    end

    def to_tree(normalized_data)
      root = normalized_data[@root]

      deep_map(root) { |k, v|
        case v
        when Hash
          type, id = v.values_at("type", "id")

          new_v =
            if type.nil?
              # Not a link
              v
            elsif id.nil?
              # Looks like link, but no ID. That's an error.
              raise ArgumentError.new("Invalid link: #{v.inspect} has a 'type' key but no 'id'")
            else
              # Is a link
              resolve_link(type, id, normalized_data)
            end

          [k, new_v]
        else
          [k, v]
        end
      }
    end

    # Recursively walks through nested hash and performs `map` operation.
    #
    # The tree is traversed in pre-order manner.
    #
    # In each node, calls the block with two arguments: key and value.
    # The block needs to return a tuple of [key, value].
    #
    # Example (double all values):
    #
    # deep_map(a: { b: { c: 1}, d: [{ e: 1, f: 2 }]}) { |k, v|
    #   [k, v * 2]
    # }
    #
    #
    # Example (stringify keys):
    #
    # deep_map(a: 1, b: 2) { |k, v|
    #   [k.to_s, v]
    # }
    #
    # Unlike Ruby's Hash#map, this method returns a Hash, not an Array.
    #
    def deep_map(obj, &block)
      case obj
      when Hash
        obj.map { |k, v|
          deep_map(block.call(k, v), &block)
        }.to_h
      when Array
        obj.map { |x| deep_map(x, &block) }
      else
        obj
      end
    end

    def self.find_link(type, id, normalized_data)
      normalized_data[type].find { |item| item["id"] == id }
    end

    private

    def resolve_link(type, id, normalized_data)
      if @link_resolvers[type].respond_to? :call
        @link_resolvers[type].call(type, id, normalized_data)
      else
        self.class.find_link(type, id, normalized_data)
      end
    end
  end

  # Needed for rendering
  #
  # See Rendering Helpers: http://api.rubyonrails.org/classes/ActionController/Metal.html
  #
  include AbstractController::Rendering
  include ActionView::Layouts
  append_view_path "#{Rails.root}/app/views"

  # Include route helpers
  include Rails.application.routes.url_helpers

  # Adds helper_method
  include ActionController::Helpers

  def index
    version = clp_version(community_id(request))
    # TODO Ideally we would do the caching based upon just clp_version
    # and avoid loading and parsing the (potentially) big structure
    # JSON.
    begin
      structure = load_structure(community_id(request), version)
      render_landing_page(structure)
    rescue LandingPageContentNotFound
      render_not_found()
    end
  end

  def preview
    preview_version = parse_int(params[:preview_version])
    begin
      structure = load_structure(community_id(request), preview_version)

      # Tell robots to not index and to not follow any links
      headers["X-Robots-Tag"] = "none"
      render_landing_page(structure)
    rescue LandingPageContentNotFound
      render_not_found()
    end
  end


  private

  def denormalizer
    # Application paths
    paths = { "search_path" => "/search/", # FIXME. Remove hardcoded URL. Add search path here when we get one
              "signup_path" => sign_up_path }

    Denormalizer.new(
      link_resolvers: {
        "path" => ->(type, id, normalized_data) {
          path = paths[id]

          if path.nil?
            raise ArgumentError.new("Couldn't find path '#{id}'")
          else
            path
          end
        },
        "marketplace_color" => ->(type, id, normalized_data) {
          case id
          when "primary_color"
            {"id" => "primary_color", "value" => "#347F9D"}
          end
        },
        "assets" => ->(type, id, normalized_data) {
          append_asset_path(Denormalizer.find_link(type, id, normalized_data))
        }
      }
    )
  end

  def parse_int(int_str_or_nil)
    Integer(int_str_or_nil || "")
  rescue ArgumentError
    nil
  end

  def clp_version(cid)
    enabled, released_version = LandingPage.where(community_id: cid)
                               .pluck(:enabled, :released_version)
                               .first
    if !enabled
      raise LandingPageConfigurationError.new("Landing page not enabled. community_id: #{cid}.")
    elsif released_version.nil?
      raise LandingPageConfigurationError.new("Landing page version not specified.")
    end

    released_version
  end

  def load_structure(cid, version)
    content = LandingPageVersion.where(community_id: cid, version: version)
              .pluck(:content)
              .first
    if content.blank?
      raise LandingPageContentNotFound.new("Content missing. community_id: #{cid}, version: #{version}.")
    end

    # For dev purposes uncomment to easily test data modifications without DB
    # content = data_str

    JSON.parse(content)
  end

  def community_id(request)
    # TODO - This will come from request.env where the to-be-implemented middleware will put the data
    ident = request.host.split(".").first
    if ident == "aalto"
      501
    elsif ident == "oin"
      11
    end
  end

  def render_landing_page(structure)
    render :landing_page,
           locals: { font_path: "/landing_page/fonts",
                     styles: landing_page_styles,
                     location_search_js: location_search_js,
                     sections: denormalizer.to_tree(structure) }
  end

  def render_not_found(msg = "Not found")
    self.status = 404
    self.response_body = msg
  end

  def append_asset_path(asset)
    asset.merge("src" => ["landing_page", asset["src"]].join("/"))
  end

  def data_str
    <<JSON
{
  "settings": {
    "marketplace_id": 9999,
    "locale": "en",
    "sitename": "turbobikes"
  },

  "sections": [
    {
      "id": "private_hero",
      "kind": "hero",
      "variation": "private",
      "title": "Your marketplace title goes here and it looks tasty",
      "subtitle": "Paragraph. Etiam porta sem malesuada magna mollis euismod. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas sed diam.",
      "background_image": {"type": "assets", "id": "myheroimage"},
      "signup_button": "Sign up",
      "signup_path": {"type": "path", "id": "signup_path"}
    },

    {
      "id": "myhero1",
      "kind": "hero",
      "variation": "location_search",
      "title": "Your marketplace title goes here and it looks tasty",
      "subtitle": "Paragraph. Etiam porta sem malesuada magna mollis euismod. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas sed diam.",
      "background_image": {"type": "assets", "id": "myheroimage"},
      "search_placeholder": "What kind of turbojopo are you looking for?",
      "search_button": "Search",
      "search_path": {"type": "path", "id": "search_path"}
    },

    {
      "id": "footer",
      "kind": "footer",
      "theme": "dark",
      "social_media_icon_color": {"type": "marketplace_color", "id": "primary_color"},
      "links": [
        {"label": "About", "url": "/about"},
        {"label": "How it works", "url": "https://www.google.com"},
        {"label": "Blog", "url": "/about"},
        {"label": "Contact", "url": "https://www.google.com"},
        {"label": "FAQ", "url": "/about"}
      ],
      "social": [
        {"service": "facebook", "url": "https://www.facebook.com"},
        {"service": "twitter", "url": "https://www.twitter.com"},
        {"service": "instagram", "url": "https://www.instagram.com"}
      ],
      "copyright": "Copyright Marketplace Ltd 2016"
    },

    {
      "id": "thecategories",
      "kind": "categories",
      "slogan": "blaablaa",
      "category_ids": [123, 432, 131]
    }
  ],

  "composition": [
    { "section": {"type": "sections", "id": "private_hero"},
      "disabled": false},
    { "section": {"type": "sections", "id": "footer"},
      "disabled": false},
    { "section": {"type": "sections", "id": "myhero1"},
      "disabled": true},
    { "section": {"type": "sections", "id": "myhero1"},
      "disabled": true}
  ],

  "assets": [
    {
      "id": "myheroimage",
      "src": "hero.jpg"
    }
  ]
}
JSON
  end

  def landing_page_styles
    Rails.application.assets.find_asset("landing_page/styles.scss").to_s
  end

  def location_search_js
    Rails.application.assets.find_asset("location_search.js").to_s
  end
end
