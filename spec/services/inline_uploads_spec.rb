# frozen_string_literal: true
require 'rails_helper'

RSpec.describe InlineUploads do
  before do
    @original_asset_host = Rails.configuration.action_controller.asset_host
    Rails.configuration.action_controller.asset_host = "https://cdn.discourse.org/stuff"
  end

  after do
    Rails.configuration.action_controller.asset_host = @original_asset_host
  end

  describe '.process' do
    describe 'local uploads' do
      fab!(:upload) { Fabricate(:upload) }
      fab!(:upload2) { Fabricate(:upload) }
      fab!(:upload3) { Fabricate(:upload) }

      it "should not correct existing inline uploads" do
        md = <<~MD
        ![test](#{upload.short_url})haha
        [test]#{upload.short_url}
        MD

        expect(InlineUploads.process(md)).to eq(md)

        md = <<~MD
        ![test](#{upload.short_url})
        [test|attachment](#{upload.short_url})
        MD

        expect(InlineUploads.process(md)).to eq(md)
      end

      it "should not escape existing content" do
        md = "1 > 2"

        expect(InlineUploads.process(md)).to eq(md)
      end

      it "should not escape invalid HTML tags" do
        md = "<x>.<y>"

        expect(InlineUploads.process(md)).to eq(md)
      end

      it "should not correct code blocks" do
        md = "`<a class=\"attachment\" href=\"#{upload2.url}\">In Code Block</a>`"

        expect(InlineUploads.process(md)).to eq(md)

        md = "    <a class=\"attachment\" href=\"#{upload2.url}\">In Code Block</a>"

        expect(InlineUploads.process(md)).to eq(md)
      end

      it "should not correct links in quotes" do
        post = Fabricate(:post)
        user = Fabricate(:user)

        md = <<~MD
        [quote="#{user.username}, post:#{post.post_number}, topic:#{post.topic.id}"]
        some quote

        #{Discourse.base_url}#{upload3.url}

        ![](#{upload.url})
        [/quote]
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        [quote="#{user.username}, post:#{post.post_number}, topic:#{post.topic.id}"]
        some quote

        ![](#{upload3.short_url})

        ![](#{upload.short_url})
        [/quote]
        MD
      end

      it "should correct markdown linked images" do
        md = <<~MD
        [![](#{upload.url})](https://somelink.com)

        [![some test](#{upload2.url})](https://somelink.com)
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        [![](#{upload.short_url})](https://somelink.com)

        [![some test](#{upload2.short_url})](https://somelink.com)
        MD
      end

      it "should correct markdown images with title" do
        md = <<~MD
        ![](#{upload.url} "some alt")
        ![testing](#{upload2.url}  'some alt'  )
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ![](#{upload.short_url} "some alt")
        ![testing](#{upload2.short_url}  'some alt'  )
        MD
      end

      it "should correct bbcode img URLs to the short version" do
        md = <<~MD
        [img]#{upload.url}[/img]

        [img]
        #{upload2.url}
        [/img]
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ![](#{upload.short_url})

        ![](#{upload2.short_url})
        MD
      end

      it "should correct markdown references" do
        md = <<~MD
        This is a [some reference] somethign

        [some reference]: #{Discourse.base_url}#{upload.url}
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        This is a [some reference] somethign

        [some reference]: #{Discourse.base_url}#{upload.short_path}
        MD
      end

      it "should correct raw image URLs to the short version" do
        md = <<~MD
        #{Discourse.base_url}#{upload3.url} #{Discourse.base_url}#{upload3.url}
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ![](#{upload3.short_url}) ![](#{upload3.short_url})
        MD
      end

      it "should correct image URLs to the short version" do
        md = <<~MD
        ![image|690x290](#{upload.short_url})

        ![IMAge|690x190,60%](#{upload.short_url})

        ![image](#{upload2.url})
        ![image|100x100](#{upload3.url})

        <img src="#{Discourse.base_url}#{upload.url}" alt="some image" title="some title" />
        <img src="#{Discourse.base_url}#{upload2.url}" alt="some image"><img src="#{Discourse.base_url}#{upload3.url}" alt="some image">

        #{Discourse.base_url}#{upload3.url} #{Discourse.base_url}#{upload3.url}

        <img src="#{upload.url}" width="5" height="4">
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ![image|690x290](#{upload.short_url})

        ![IMAge|690x190,60%](#{upload.short_url})

        ![image](#{upload2.short_url})
        ![image|100x100](#{upload3.short_url})

        ![some image](#{upload.short_url} "some title")
        ![some image](#{upload2.short_url})![some image](#{upload3.short_url})

        ![](#{upload3.short_url}) ![](#{upload3.short_url})

        ![|5x4](#{upload.short_url})
        MD
      end

      it "should not be affected by an emoji" do
        CustomEmoji.create!(name: 'test', upload: upload3)
        Emoji.clear_cache

        md = <<~MD
        :test:

        ![image|690x290](#{upload.url})
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        :test:

        ![image|690x290](#{upload.short_url})
        MD
      end

      it "should correctly update image sources within anchor or paragraph tags" do
        md = <<~MD
        <a href="http://somelink.com">
          <img src="#{upload.url}" alt="test" width="500" height="500">
        </a>

        <p>
          <img src="#{upload2.url}" alt="test">
        </p>

        <a href="http://somelink.com"><img src="#{upload3.url}" alt="test" width="500" height="500"></a>

        <a href="http://somelink.com">  <img src="#{upload.url}" alt="test" width="500" height="500">  </a>

        <a href="http://somelink.com">


        <img src="#{upload.url}" alt="test" width="500" height="500">

        </a>

        <p>Test <img src="#{upload2.url}" alt="test" width="500" height="500"></p>

        <hr/>
        <img src="#{upload2.url}" alt="test" width="500" height="500">
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        <a href="http://somelink.com">

          ![test|500x500](#{upload.short_url})

        </a>

        <p>

          ![test](#{upload2.short_url})

        </p>

        <a href="http://somelink.com">

          ![test|500x500](#{upload3.short_url})

        </a>

        <a href="http://somelink.com">

          ![test|500x500](#{upload.short_url})

        </a>

        <a href="http://somelink.com">


          ![test|500x500](#{upload.short_url})

        </a>

        <p>Test ![test|500x500](#{upload2.short_url})</p>

        <hr/>

        ![test|500x500](#{upload2.short_url})
        MD
      end

      it "should not be affected by fake HTML tags" do
        md = <<~MD
        ```
        This is some <img src=" and <a href="
        ```

        <img src="#{upload.url}" alt="test">

        > some quote

        <a class="attachment" href="#{upload2.url}">test2</a>
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ```
        This is some <img src=" and <a href="
        ```

        ![test](#{upload.short_url})

        > some quote

        [test2|attachment](#{upload2.short_url})
        MD
      end

      it "should not be affected by an external or invalid links" do
        md = <<~MD
        <a id="test">invalid</a>

        [test]("https://this.is.some.external.link")

        <a href="https://some.external.com/link">test</a>

        <a class="attachment" href="#{upload2.url}">test2</a>
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        <a id="test">invalid</a>

        [test]("https://this.is.some.external.link")

        <a href="https://some.external.com/link">test</a>

        [test2|attachment](#{upload2.short_url})
        MD
      end

      it "should correct attachment URLS to the short version when raw contains inline image" do
        md = <<~MD
        ![image](#{upload.short_url}) ![image](#{upload.short_url})

        [some complicated.doc %50](#{upload3.url})

        <a class="attachment" href="#{upload2.url}">test2</a>
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ![image](#{upload.short_url}) ![image](#{upload.short_url})

        [some complicated.doc %50](#{upload3.short_url})

        [test2|attachment](#{upload2.short_url})
        MD
      end

      it "should correct attachment URLs to the short version" do
        md = <<~MD
        <a class="attachment" href="#{upload.url}">
          this
          is
          some
          attachment

        </a>

        - <a class="attachment" href="#{upload.url}">test2</a>
          - <a class="attachment" href="#{upload2.url}">test2</a>
            - <a class="attachment" href="#{upload3.url}">test2</a>

        <a class="test attachment" href="#{upload.url}">test3</a>
        <a class="test attachment" href="#{upload2.url}">test3</a><a class="test attachment" href="#{upload3.url}">test3</a>
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        [this is some attachment|attachment](#{upload.short_url})

        - [test2|attachment](#{upload.short_url})
          - [test2|attachment](#{upload2.short_url})
            - [test2|attachment](#{upload3.short_url})

        [test3|attachment](#{upload.short_url})
        [test3|attachment](#{upload2.short_url})[test3|attachment](#{upload3.short_url})
        MD
      end

      it 'should correct full upload url to the shorter version' do
        md = <<~MD
        Some random text

        ![test](#{upload.short_url})
        [test|attachment](#{upload.short_url})

        <a class="test attachment" href="#{upload.url}">
          test
        </a>

        `<a class="attachment" href="#{upload2.url}">In Code Block</a>`

            <a class="attachment" href="#{upload3.url}">In Code Block</a>

        <a href="#{upload.url}">newtest</a>
        <a href="#{Discourse.base_url_no_prefix}#{upload.url}">newtest</a>

        <a href="https://somerandomesite.com#{upload.url}">test</a>
        <a class="attachment" href="https://somerandom.com/url">test</a>
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        Some random text

        ![test](#{upload.short_url})
        [test|attachment](#{upload.short_url})

        [test|attachment](#{upload.short_url})

        `<a class="attachment" href="#{upload2.url}">In Code Block</a>`

            <a class="attachment" href="#{upload3.url}">In Code Block</a>

        [newtest](#{upload.short_url})
        [newtest](#{upload.short_url})

        <a href="https://somerandomesite.com#{upload.url}">test</a>
        <a class="attachment" href="https://somerandom.com/url">test</a>
        MD
      end

      it 'accepts a block that yields when link does not match an upload in the db' do
        url = "#{Discourse.base_url}#{upload.url}"

        md = <<~MD
        <img src="#{url}" alt="some image">
        <img src="#{upload2.url}" alt="some image">
        MD

        upload.destroy!

        InlineUploads.process(md, on_missing: lambda { |link|
          expect(link).to eq(url)
        })
      end
    end

    describe "s3 uploads" do
      let(:upload) { Fabricate(:upload_s3) }
      let(:upload2) { Fabricate(:upload_s3) }

      before do
        SiteSetting.enable_s3_uploads = true
        SiteSetting.s3_upload_bucket = "s3-upload-bucket"
        SiteSetting.s3_access_key_id = "some key"
        SiteSetting.s3_secret_access_key = "some secret key"
        SiteSetting.s3_cdn_url = "https://s3.cdn.com"
      end

      it "should correct image URLs to the short version" do
        md = <<~MD
        <img src="#{upload.url}" alt="some image">
        <img src="#{URI.join(SiteSetting.s3_cdn_url, URI.parse(upload2.url).path).to_s}" alt="some image">
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        ![some image](#{upload.short_url})
        ![some image](#{upload2.short_url})
        MD
      end

      it "should correct markdown references" do
        md = <<~MD
        This is a [some reference] somethign

        [some reference]: https:#{upload.url}
        MD

        expect(InlineUploads.process(md)).to eq(<<~MD)
        This is a [some reference] somethign

        [some reference]: #{Discourse.base_url}#{upload.short_path}
        MD
      end

      it "should correct image URLs in multisite" do
        begin
          Rails.configuration.multisite = true

          md = <<~MD
          https:#{upload2.url} https:#{upload2.url}
          #{URI.join(SiteSetting.s3_cdn_url, URI.parse(upload2.url).path).to_s}

          <img src="#{upload.url}" alt="some image">
          <img src="#{URI.join(SiteSetting.s3_cdn_url, URI.parse(upload2.url).path).to_s}" alt="some image">
          MD

          expect(InlineUploads.process(md)).to eq(<<~MD)
          ![](#{upload2.short_url}) ![](#{upload2.short_url})
          ![](#{upload2.short_url})

          ![some image](#{upload.short_url})
          ![some image](#{upload2.short_url})
          MD
        ensure
          Rails.configuration.multisite = false
        end
      end
    end
  end
end
