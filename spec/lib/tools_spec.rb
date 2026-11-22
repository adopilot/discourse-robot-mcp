# frozen_string_literal: true

describe RobotMcp::Tools do
  def request_context(user)
    instance_double(DiscourseMcp::RequestContext, user:, user_id: user.id, guardian: user.guardian)
  end

  fab!(:it_group, :group)
  fab!(:member) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:outsider) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:wiki) { Fabricate(:category, name: "IT-Wiki") }
  fab!(:general) { Fabricate(:category, name: "Opšte") }
  fab!(:secret_group, :group)
  fab!(:hidden) { Fabricate(:private_category, group: secret_group, name: "Skriveno") }
  fab!(:general_topic) do
    Fabricate(:topic, category: general, title: "Mikrotik u skladištu Ilidža")
  end
  fab!(:general_post) do
    Fabricate(:post, topic: general_topic, raw: "Mikrotik u skladištu, lozinka je u trezoru")
  end
  fab!(:hidden_topic) { Fabricate(:topic, category: hidden, title: "Skrivena tema o Mikrotiku") }
  fab!(:hidden_post) { Fabricate(:post, topic: hidden_topic, raw: "Mikrotik tajna tema") }

  before do
    SiteSetting.robot_mcp_enabled = true
    SiteSetting.robot_mcp_wiki_category_id = wiki.id
    SiteSetting.robot_mcp_allowed_groups = it_group.id.to_s
    SiteSetting.robot_mcp_read_categories = ""
    it_group.add(member)
  end

  def call(mod, user, args)
    mod.call(arguments: args, request_context: request_context(user))
  end

  def structured(result)
    result[:structuredContent] || result["structuredContent"] || result
  end

  describe "reading" do
    it "reads any topic the user can see when no category limit is set" do
      out = structured(call(RobotMcp::Tools::ReadTopic, member, { "topic_id" => general_topic.id }))
      expect(out[:posts].first[:raw]).to include("Mikrotik")
    end

    it "never reads topics the user cannot see" do
      expect {
        call(RobotMcp::Tools::ReadTopic, member, { "topic_id" => hidden_topic.id })
      }.to raise_error(DiscourseMcp::ToolError)
    end

    it "never reads private messages" do
      pm = Fabricate(:private_message_topic, user: member)
      Fabricate(:post, topic: pm, user: member)
      expect { call(RobotMcp::Tools::ReadTopic, member, { "topic_id" => pm.id }) }.to raise_error(
        DiscourseMcp::ToolError,
      )
    end

    it "still honours a configured category limit" do
      SiteSetting.robot_mcp_read_categories = wiki.id.to_s
      expect {
        call(RobotMcp::Tools::ReadTopic, member, { "topic_id" => general_topic.id })
      }.to raise_error(DiscourseMcp::ToolError)
    end

    it "searches everything visible" do
      SearchIndexer.enable
      SearchIndexer.index(general_post, force: true)
      SearchIndexer.index(hidden_post, force: true)
      out = structured(call(RobotMcp::Tools::Search, member, { "query" => "Mikrotik" }))
      ids = out[:results].map { |r| r[:topic_id] }
      expect(ids).to include(general_topic.id)
      expect(ids).not_to include(hidden_topic.id)
    end

    it "is only for the allowed groups" do
      expect {
        call(RobotMcp::Tools::ReadTopic, outsider, { "topic_id" => general_topic.id })
      }.to raise_error(DiscourseMcp::ToolError)
    end
  end

  describe "writing" do
    it "replies in any topic the user may post in" do
      out =
        structured(
          call(
            RobotMcp::Tools::Reply,
            member,
            {
              "topic_id" => general_topic.id,
              "raw" => "Dopuna: lozinka: [vault ask=\"Mikrotik admin\"]",
            },
          ),
        )
      expect(out[:post_number]).to eq(2)
      expect(general_topic.reload.posts.last.user).to eq(member)
    end

    it "refuses closed topics" do
      general_topic.update!(closed: true)
      expect {
        call(
          RobotMcp::Tools::Reply,
          member,
          { "topic_id" => general_topic.id, "raw" => "odgovor ovdje" },
        )
      }.to raise_error(DiscourseMcp::ToolError)
    end

    it "refuses passwords" do
      expect {
        call(
          RobotMcp::Tools::Reply,
          member,
          { "topic_id" => general_topic.id, "raw" => "lozinka: Hunter2!xyz" },
        )
      }.to raise_error(DiscourseMcp::ToolError, /trezor/)
    end

    it "creates topics in a chosen category, IT-Wiki by default" do
      out =
        structured(
          call(
            RobotMcp::Tools::CreateTopic,
            member,
            {
              "title" => "Novi server za backup u Mostaru",
              "raw" => "Server je podešen, lozinka: [vault ask=\"Backup server root\"]",
              "category_id" => general.id,
            },
          ),
        )
      expect(Topic.find(out[:topic_id]).category).to eq(general)

      out =
        structured(
          call(
            RobotMcp::Tools::CreateTopic,
            member,
            {
              "title" => "Dokumentacija za novi switch",
              "raw" => "Switch je podešen i radi uredno.",
            },
          ),
        )
      expect(Topic.find(out[:topic_id]).category).to eq(wiki)
    end

    it "refuses categories the user cannot post in" do
      expect {
        call(
          RobotMcp::Tools::CreateTopic,
          member,
          {
            "title" => "Pokušaj u skrivenoj kategoriji",
            "raw" => "Ovo ne bi smjelo proći.",
            "category_id" => hidden.id,
          },
        )
      }.to raise_error(DiscourseMcp::ToolError)
    end
  end
end
