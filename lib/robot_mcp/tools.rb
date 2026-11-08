# frozen_string_literal: true

module ::RobotMcp
  module Tools
    READ_ONLY = {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    }.freeze
    WRITE = {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false,
    }.freeze
    MAX_READ_LENGTH = 50_000

    DOCUMENT_INSTRUCTIONS = <<~TEXT
      Dokumentuj u IT-Wiki (forum.robot.ba) ono što je urađeno u ovoj sesiji.

      1. Prvo pozovi robot_search da vidiš postoji li već tema za taj server, lokaciju ili sistem.
         Ako postoji, predloži dopunu (robot_wiki_reply), inače novu temu (robot_wiki_create_topic).
      2. Piši na bosanskom, jasno, za kolegu iz IT-a koji za godinu dana treba ponoviti ili provjeriti posao.
      3. Obrazac:
         **Ukratko:** 2-3 rečenice šta je urađeno i zašto.
         ## Okruženje
         Serveri, IP adrese, lokacije, verzije.
         ## Šta je urađeno
         Koraci redom, komande i konfiguracije u blokovima koda.
         ## Kako provjeriti / vratiti
         ## Otvorene stavke
         Lista sa [ ] za ono što je ostalo.
      4. NIKAD ne upisuj lozinke, ključeve, tokene ni connection stringove sa lozinkom.
         Umjesto vrijednosti napiši "lozinka: u trezoru".
      5. Prije objave pozovi robot_check_secrets, pa korisniku pokaži cijeli nacrt i gdje ide
         (nova tema sa naslovom ili dopuna postojeće). Objavi tek kad korisnik potvrdi.
      6. Korisnička imena ne piši sa @ (to šalje obavijesti i poziva AI botove), osim ako korisnik to izričito traži.
    TEXT

    REPORT_INSTRUCTIONS = <<~TEXT
      Javi na forum (forum.robot.ba) napredak rada iz ove sesije, kao odgovor u temu koja je dodijeljena korisniku.

      1. Vrsta odgovora. Ako je korisnik nije rekao, pitaj ga koju želi:
         - Status: dokle se stiglo
         - Urađeno: šta je završeno i kako provjeriti
         - Sljedeći koraci: plan, šta slijedi i šta je potrebno
         - Pitanje: šta treba od podnosioca ili kolege
         "Objavi status" znači Status, "pitaj na forumu" znači Pitanje.
      2. Tema. Pozovi robot_my_tasks, po potrebi sa ključnim riječima iz posla. Teme sa recently_reported=true su one u koje
         je korisnik zadnje javljao. Ako se jedna jasno poklapa sa poslom, predloži nju, inače ponudi 3-5 najbližih i pitaj.
         Ne pamti broj teme u svojoj memoriji ni u CLAUDE.md: dodjele se mijenjaju, uvijek ih provjeri kroz robot_my_tasks.
      3. Pozovi robot_task_context da vidiš zadatak (prvi post) i dokle se stiglo (zadnji odgovori).
      4. Napiši kratak odgovor na bosanskom, prilagođen vrsti:
         - Status: **Status:** jedna rečenica, **Urađeno:** lista, **Sljedeće:** lista
         - Urađeno: šta je završeno i kako se provjerava
         - Sljedeći koraci: koraci redom i šta je za njih potrebno
         - Pitanje: jasno pitanje i kontekst u 1-2 rečenice
      5. NIKAD ne upisuj lozinke, ključeve ni tokene; umjesto vrijednosti napiši "lozinka: u trezoru".
         Korisnike spominji sa @ samo ako korisnik želi da ih obavijesti; AI botove nikad.
      6. Pozovi robot_check_secrets, pokaži korisniku nacrt i temu, a objavi (robot_task_reply) tek kad potvrdi.
         Ako robot_task_reply javi da tema više nije dodijeljena korisniku, reci mu kome je dodijeljena i ponudi njegove trenutne zadatke.
      7. Poslije objave pokaži korisniku erp_time_url iz rezultata: tu upisuje utrošeno vrijeme u ERP
         (forma može i označiti post kao rješenje).
      8. Temu označi riješenom (robot_task_solve) SAMO kad korisnik to izričito kaže.
         Zatvaranje (robot_task_close) i prebacivanje kolegi (robot_task_reassign) radi tek kad korisnik potvrdi
         tačno tu temu i tu radnju; tek tada pozovi alat sa confirmed=true.
    TEXT

    CLEANUP_INSTRUCTIONS = <<~TEXT
      Pomozi korisniku da očisti stare obaveze na forumu (forum.robot.ba).

      1. Pozovi robot_my_tasks sa sort="oldest" i inactive_days (npr. 60), po potrebi više puta.
      2. Grupiši teme i za svaku predloži jednu radnju:
         - Riješeno: zadnji post kaže da radi ili je posao očito završen → označiti riješenom ili zatvoriti
         - Čeka korisnika: zadnji je pisao neko iz IT-a → zatvoriti uz kratku napomenu da otvore novu temu ako problem postoji
         - Čeka IT: zadnji je pisao korisnik (waiting_on_it=true) → NE zatvarati; uraditi ili prebaciti kolegi
         - Nije moje: predložiti kolegu iz IT-a
         Kad nije jasno, pozovi robot_task_context za tu temu.
      3. Pokaži prijedlog kao listu (tema, link, radnja) u grupama od najviše 15 tema.
      4. Ništa ne mijenjaj dok korisnik ne potvrdi. Korisnik može potvrditi sve, dio ("sve osim 3 i 7") ili ništa.
      5. Za potvrđene teme pozovi robot_task_solve, robot_task_close ili robot_task_reassign sa confirmed=true,
         jednu po jednu, i na kraju javi šta je urađeno, a šta nije uspjelo i zašto.
      6. Napomene pri zatvaranju piši kratko i ljubazno, bez lozinki, i bez @ spominjanja.
    TEXT

    REPORT_KINDS = %w[status uradjeno sljedeci_koraci pitanje].freeze
    ACTION_FIELD = "robot_mcp_action"
    REPORTED_FIELD = "robot_mcp_report"
    RECENT_REPORT_DAYS = 30

    module_function

    def register!(plugin)
      plugin.register_mcp_tool(
        "robot_search",
        title: "Pretraga IT dokumentacije",
        description:
          "Pretražuje IT-Wiki i ostale dozvoljene IT kategorije foruma. Vraća teme sa kratkim izvodom. " \
            "Koristi prije pisanja dokumentacije da nađeš postojeću temu.",
        implementation: Search,
        input_schema:
          object_schema(
            {
              query: {
                type: "string",
                minLength: 1,
                maxLength: 500,
              },
              max_results: {
                type: "integer",
                minimum: 1,
                maximum: 20,
              },
            },
            required: %w[query],
          ),
        output_schema: Search::OUTPUT_SCHEMA,
        required_scopes: Search::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_tool(
        "robot_read_topic",
        title: "Čitanje teme",
        description: "Čita postove teme iz IT-Wiki ili druge dozvoljene IT kategorije.",
        implementation: ReadTopic,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              max_posts: {
                type: "integer",
                minimum: 1,
                maximum: 100,
              },
            },
            required: %w[topic_id],
          ),
        output_schema: ReadTopic::OUTPUT_SCHEMA,
        required_scopes: ReadTopic::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_tool(
        "robot_check_secrets",
        title: "Provjera tajnih podataka",
        description:
          "Provjerava nacrt prije objave: traži lozinke, ključeve i tokene. Vraća vrstu i red nalaza, nikad samu vrijednost.",
        implementation: CheckSecrets,
        input_schema:
          object_schema({ text: { type: "string", minLength: 1, maxLength: 60_000 } }, required: %w[text]),
        output_schema: CheckSecrets::OUTPUT_SCHEMA,
        required_scopes: CheckSecrets::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_tool(
        "robot_wiki_create_topic",
        title: "Nova tema u IT-Wiki",
        description:
          "Objavljuje novu temu u IT-Wiki kao prijavljeni korisnik. Pozovi tek kad korisnik potvrdi nacrt. " \
            "Tekst sa lozinkama, ključevima ili tokenima biće odbijen.",
        implementation: CreateWikiTopic,
        input_schema:
          object_schema(
            {
              title: {
                type: "string",
                minLength: 5,
                maxLength: 255,
              },
              raw: {
                type: "string",
                minLength: 20,
                maxLength: 30_000,
              },
              tags: {
                type: "array",
                items: {
                  type: "string",
                },
                maxItems: 5,
              },
            },
            required: %w[title raw],
          ),
        output_schema: CreateWikiTopic::OUTPUT_SCHEMA,
        required_scopes: CreateWikiTopic::REQUIRED_SCOPES,
        annotations: WRITE,
        risk: :write,
      )

      plugin.register_mcp_tool(
        "robot_wiki_reply",
        title: "Dopuna teme u IT-Wiki",
        description:
          "Dodaje odgovor (dopunu dokumentacije) u postojeću temu u IT-Wiki kao prijavljeni korisnik. " \
            "Pozovi tek kad korisnik potvrdi nacrt. Tekst sa lozinkama, ključevima ili tokenima biće odbijen.",
        implementation: WikiReply,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              raw: {
                type: "string",
                minLength: 20,
                maxLength: 30_000,
              },
            },
            required: %w[topic_id raw],
          ),
        output_schema: WikiReply::OUTPUT_SCHEMA,
        required_scopes: WikiReply::REQUIRED_SCOPES,
        annotations: WRITE,
        risk: :write,
      )

      plugin.register_mcp_tool(
        "robot_my_tasks",
        title: "Moje obaveze",
        description:
          "Otvorene, neriješene teme dodijeljene prijavljenom korisniku (isto kao /latest?assigned=<korisnik>&solved=no&status=open). " \
            "Jedan red po temi. Teme u koje je korisnik zadnje javljao (recently_reported) su na vrhu. " \
            "Ključne riječi iz posla suzavaju listu. Za čišćenje starih obaveza: sort=\"oldest\" i inactive_days. " \
            "waiting_on_it=true znači da je zadnji pisao neko izvan IT tima (čeka se odgovor IT-a).",
        implementation: MyTasks,
        input_schema:
          object_schema(
            {
              keywords: {
                type: "string",
                maxLength: 200,
              },
              max_results: {
                type: "integer",
                minimum: 1,
                maximum: 30,
              },
              sort: {
                type: "string",
                enum: %w[relevant oldest],
              },
              inactive_days: {
                type: "integer",
                minimum: 1,
                maximum: 3650,
              },
            },
          ),
        output_schema: MyTasks::OUTPUT_SCHEMA,
        required_scopes: MyTasks::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_tool(
        "robot_task_context",
        title: "Kontekst zadatka",
        description:
          "Za temu dodijeljenu prijavljenom korisniku vraća prvi post (zadatak) i zadnjih nekoliko odgovora (dokle se stiglo).",
        implementation: TaskContext,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              last_posts: {
                type: "integer",
                minimum: 0,
                maximum: 20,
              },
            },
            required: %w[topic_id],
          ),
        output_schema: TaskContext::OUTPUT_SCHEMA,
        required_scopes: TaskContext::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_tool(
        "robot_task_reply",
        title: "Javi u dodijeljenu temu",
        description:
          "Objavljuje odgovor u temu koja je TRENUTNO dodijeljena prijavljenom korisniku (dodjela se provjerava pri objavi). " \
            "Pozovi tek kad korisnik potvrdi nacrt i vrstu odgovora. Za zatvorenu ili riješenu temu traži confirm_closed=true " \
            "nakon što korisnik potvrdi. Tekst sa lozinkama, ključevima ili tokenima biće odbijen.",
        implementation: TaskReply,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              kind: {
                type: "string",
                enum: REPORT_KINDS,
              },
              raw: {
                type: "string",
                minLength: 10,
                maxLength: 30_000,
              },
              confirm_closed: {
                type: "boolean",
              },
            },
            required: %w[topic_id kind raw],
          ),
        output_schema: TaskReply::OUTPUT_SCHEMA,
        required_scopes: TaskReply::REQUIRED_SCOPES,
        annotations: WRITE,
        risk: :write,
      )

      plugin.register_mcp_tool(
        "robot_task_solve",
        title: "Označi riješeno",
        description:
          "Označava post kao rješenje (solved) u temi koja je TRENUTNO dodijeljena prijavljenom korisniku. " \
            "Pozovi SAMO kad korisnik izričito kaže da je tema riješena. Bez post_number uzima zadnji post korisnika u temi. " \
            "Vraća i erp_time_url za upis utrošenog vremena.",
        implementation: TaskSolve,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              post_number: {
                type: "integer",
                minimum: 2,
              },
            },
            required: %w[topic_id],
          ),
        output_schema: TaskSolve::OUTPUT_SCHEMA,
        required_scopes: TaskSolve::REQUIRED_SCOPES,
        annotations: WRITE,
        risk: :write,
      )

      plugin.register_mcp_tool(
        "robot_task_close",
        title: "Zatvori temu",
        description:
          "Zatvara temu koja je TRENUTNO dodijeljena prijavljenom korisniku, po želji uz kratku napomenu (raw). " \
            "Pozovi tek kad korisnik potvrdi tačno ovu temu, i tada pošalji confirmed=true. " \
            "Napomena sa lozinkama, ključevima ili tokenima biće odbijena.",
        implementation: TaskClose,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              raw: {
                type: "string",
                minLength: 10,
                maxLength: 5_000,
              },
              confirmed: {
                type: "boolean",
              },
            },
            required: %w[topic_id confirmed],
          ),
        output_schema: TaskClose::OUTPUT_SCHEMA,
        required_scopes: TaskClose::REQUIRED_SCOPES,
        annotations: WRITE,
        risk: :write,
      )

      plugin.register_mcp_tool(
        "robot_task_reassign",
        title: "Prebaci temu kolegi",
        description:
          "Prebacuje temu koja je TRENUTNO dodijeljena prijavljenom korisniku na kolegu iz IT tima (username), " \
            "po želji uz kratku napomenu (raw). Pozovi tek kad korisnik potvrdi temu i kolegu, i tada pošalji confirmed=true. " \
            "Napomena sa lozinkama, ključevima ili tokenima biće odbijena.",
        implementation: TaskReassign,
        input_schema:
          object_schema(
            {
              topic_id: {
                type: "integer",
                minimum: 1,
              },
              username: {
                type: "string",
                minLength: 2,
                maxLength: 60,
              },
              raw: {
                type: "string",
                minLength: 10,
                maxLength: 5_000,
              },
              confirmed: {
                type: "boolean",
              },
            },
            required: %w[topic_id username confirmed],
          ),
        output_schema: TaskReassign::OUTPUT_SCHEMA,
        required_scopes: TaskReassign::REQUIRED_SCOPES,
        annotations: WRITE,
        risk: :write,
      )

      plugin.register_mcp_prompt(
        "robot.ocisti",
        title: "Očisti stare obaveze",
        description: "Upute za pregled starih dodijeljenih tema i prijedlog šta zatvoriti, riješiti ili prebaciti.",
        implementation: CleanupPrompt,
        input_schema:
          object_schema({ opis: { type: "string", maxLength: 1000 } }),
        required_scopes: CleanupPrompt::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_prompt(
        "robot.javi",
        title: "Javi ovo na forum",
        description:
          "Upute za javljanje napretka (status, urađeno, sljedeći koraci, pitanje) u temu dodijeljenu korisniku.",
        implementation: ReportPrompt,
        input_schema:
          object_schema({ opis: { type: "string", maxLength: 1000 } }),
        required_scopes: ReportPrompt::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )

      plugin.register_mcp_prompt(
        "robot.dokumentuj",
        title: "Dokumentuj u IT-Wiki",
        description: "Upute za pisanje dokumentacije o urađenom poslu u IT-Wiki, bez lozinki.",
        implementation: DocumentPrompt,
        input_schema:
          object_schema({ opis: { type: "string", maxLength: 1000 } }),
        required_scopes: DocumentPrompt::REQUIRED_SCOPES,
        annotations: READ_ONLY,
      )
    end

    def object_schema(properties, required: [])
      { type: "object", properties: properties, required: required, additionalProperties: false }
    end

    def wiki_category_id
      SiteSetting.robot_mcp_wiki_category_id.to_i
    end

    def read_category_ids
      SiteSetting.robot_mcp_read_categories.to_s.split("|").map(&:to_i).push(wiki_category_id).uniq -
        [0]
    end

    def ensure_member!(request_context)
      user = request_context.user
      if user.blank? || !user.in_any_groups?(SiteSetting.robot_mcp_allowed_groups_map)
        raise DiscourseMcp::ToolError, "Ovaj alat je dostupan samo članovima IT tima."
      end
      user
    end

    def find_topic!(topic_id, request_context, category_ids)
      topic = ::Topic.find_by(id: topic_id)
      if topic.blank? || topic.private_message? || !category_ids.include?(topic.category_id) ||
           !request_context.guardian.can_see?(topic)
        raise DiscourseMcp::ToolError,
              "Tema nije pronađena ili nije u dozvoljenoj kategoriji."
      end
      topic
    end

    def create_post!(user, **attributes)
      creator = PostCreator.new(user, **attributes)
      post = creator.create
      if creator.errors.present? || post.blank? || !post.persisted?
        raise DiscourseMcp::ToolError, creator.errors.full_messages.join(", ").presence || "Objava nije uspjela."
      end
      post
    end

    def result(value)
      DiscourseMcp::ToolHelpers.text_and_structured(value)
    end

    def my_open_tasks(user)
      TopicQuery
        .new(user, assigned: user.username, solved: "no", status: "open", per_page: 1000)
        .list_latest
        .topics
    end

    def assigned_to?(topic, user)
      Assignment.where(
        active: true,
        topic_id: topic.id,
        assigned_to_type: "User",
        assigned_to_id: user.id,
      ).exists?
    end

    def assignees(topic)
      Assignment
        .where(active: true, topic_id: topic.id)
        .map { |a| a.assigned_to.try(:username) || a.assigned_to.try(:name) }
        .compact
        .uniq
    end

    # The assignment is the filter: categories don't matter, only who the topic is assigned to now.
    def find_assigned_topic!(topic_id, request_context)
      user = request_context.user
      topic = ::Topic.find_by(id: topic_id)
      if topic.blank? || !request_context.guardian.can_see?(topic)
        raise DiscourseMcp::ToolError, "Tema ##{topic_id} nije pronađena."
      end
      if !assigned_to?(topic, user)
        others = assignees(topic)
        message =
          if others.present?
            "Tema ##{topic.id} više nije dodijeljena tebi, sada je dodijeljena: #{others.join(", ")}."
          else
            "Tema ##{topic.id} nije dodijeljena tebi (trenutno nije dodijeljena nikome)."
          end
        raise DiscourseMcp::ToolError,
              "#{message} Ponudi korisniku njegove trenutne zadatke (robot_my_tasks)."
      end
      topic
    end

    def solved?(topic)
      DB.query_single(
        "SELECT 1 FROM discourse_solved_solved_topics WHERE topic_id = ? LIMIT 1",
        topic.id,
      ).present?
    end

    def ensure_confirmed!(arguments, what)
      return if arguments["confirmed"] == true
      raise DiscourseMcp::ToolError,
            "#{what} traži potvrdu korisnika. Pokaži korisniku temu i radnju, pa pozovi ponovo sa confirmed=true tek kad potvrdi."
    end

    def it_member?(user)
      user.present? && user.in_any_groups?(SiteSetting.robot_mcp_allowed_groups_map)
    end

    def erp_time_url(post, user)
      base = SiteSetting.robot_mcp_erp_task_url.to_s.strip
      return nil if base.blank? || post.blank?
      query = {
        url: Discourse.base_url,
        user: user.username,
        topicId: post.topic_id,
        postId: post.id,
        postNumber: post.post_number,
      }.to_query
      "#{base}#{base.include?("?") ? "&" : "?"}#{query}"
    end

    def create_note!(user, topic, raw, action)
      return nil if raw.blank?
      SecretScanner.ensure_clean!(raw)
      post = create_post!(user, topic_id: topic.id, raw: raw)
      post.custom_fields[ACTION_FIELD] = action
      post.save_custom_fields
      post
    end

    def truncate(text, limit)
      text.length > limit ? "#{text[0, limit]}\n[… skraćeno]" : text
    end

    module Search
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(results: DiscourseMcp::OutputSchema::OBJECT_ARRAY)

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        category_ids = Tools.read_category_ids
        limit = arguments.fetch("max_results", 10).to_i
        query = "#{arguments.fetch("query")} categories:#{category_ids.map { |id| "=#{id}" }.join(",")}"
        results =
          ::Search.execute(
            query,
            guardian: request_context.guardian,
            type_filter: "topic",
            search_type: :full_page,
            exclude_private_messages: true,
          )
        posts =
          results
            .posts
            .select { |post| category_ids.include?(post.topic&.category_id) }
            .uniq(&:topic_id)
            .first(limit)
        Tools.result(
          results:
            posts.map do |post|
              {
                topic_id: post.topic_id,
                post_number: post.post_number,
                title: post.topic.title,
                category: post.topic.category&.name,
                url: post.full_url,
                excerpt: PrettyText.excerpt(post.cooked, 300, strip_links: true),
              }
            end,
        )
      end
    end

    module ReadTopic
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic: DiscourseMcp::OutputSchema::OBJECT,
          posts: DiscourseMcp::OutputSchema::OBJECT_ARRAY,
          truncated: DiscourseMcp::OutputSchema::BOOLEAN,
        )

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        topic = Tools.find_topic!(arguments.fetch("topic_id"), request_context, Tools.read_category_ids)
        posts =
          topic
            .posts
            .secured(request_context.guardian)
            .where(deleted_at: nil)
            .order(:post_number)
            .limit(arguments.fetch("max_posts", 50).to_i)
        length = 0
        truncated = false
        rows =
          posts.filter_map do |post|
            next if truncated
            length += post.raw.length
            if length > MAX_READ_LENGTH
              truncated = true
              next
            end
            {
              post_number: post.post_number,
              username: post.username,
              created_at: post.created_at.iso8601,
              raw: post.raw,
            }
          end
        Tools.result(
          topic: {
            id: topic.id,
            title: topic.title,
            category: topic.category&.name,
            url: topic.url,
            posts_count: topic.posts_count,
          },
          posts: rows,
          truncated: truncated,
        )
      end
    end

    module CheckSecrets
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          clean: DiscourseMcp::OutputSchema::BOOLEAN,
          findings: DiscourseMcp::OutputSchema::OBJECT_ARRAY,
        )

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        findings = SecretScanner.scan(arguments.fetch("text"))
        Tools.result(clean: findings.empty?, findings: findings)
      end
    end

    module CreateWikiTopic
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_WRITE].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic_id: DiscourseMcp::OutputSchema::INTEGER,
          title: DiscourseMcp::OutputSchema::STRING,
          url: DiscourseMcp::OutputSchema::STRING,
          username: DiscourseMcp::OutputSchema::STRING,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        if Tools.wiki_category_id.zero?
          raise DiscourseMcp::ToolError, "Kategorija za IT-Wiki nije podešena."
        end
        SecretScanner.ensure_clean!(arguments.fetch("title"), arguments.fetch("raw"))
        post =
          Tools.create_post!(
            user,
            title: arguments.fetch("title"),
            raw: arguments.fetch("raw"),
            category: Tools.wiki_category_id,
            tags: Array(arguments["tags"]),
          )
        Tools.result(
          topic_id: post.topic_id,
          title: post.topic.title,
          url: post.topic.url,
          username: post.user.username,
        )
      end
    end

    module WikiReply
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_WRITE].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic_id: DiscourseMcp::OutputSchema::INTEGER,
          post_number: DiscourseMcp::OutputSchema::INTEGER,
          url: DiscourseMcp::OutputSchema::STRING,
          username: DiscourseMcp::OutputSchema::STRING,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        topic = Tools.find_topic!(arguments.fetch("topic_id"), request_context, [Tools.wiki_category_id])
        SecretScanner.ensure_clean!(arguments.fetch("raw"))
        post = Tools.create_post!(user, topic_id: topic.id, raw: arguments.fetch("raw"))
        Tools.result(
          topic_id: post.topic_id,
          post_number: post.post_number,
          url: post.full_url,
          username: post.user.username,
        )
      end
    end

    module MyTasks
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          tasks: DiscourseMcp::OutputSchema::OBJECT_ARRAY,
          total_open: DiscourseMcp::OutputSchema::INTEGER,
          matching: DiscourseMcp::OutputSchema::INTEGER,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        topics = Tools.my_open_tasks(user)
        ids = topics.map(&:id)

        reported =
          PostCustomField
            .joins(:post)
            .where(name: REPORTED_FIELD, posts: { topic_id: ids, user_id: user.id })
            .where("posts.created_at > ?", RECENT_REPORT_DAYS.days.ago)
            .group("posts.topic_id")
            .maximum("posts.created_at")
        my_last_post = Post.where(topic_id: ids, user_id: user.id).group(:topic_id).maximum(:created_at)

        words = arguments["keywords"].to_s.downcase.scan(/[\p{L}\p{N}_.-]{3,}/).uniq
        score = {}
        if words.present?
          first_posts = Post.where(topic_id: ids, post_number: 1).pluck(:topic_id, :raw).to_h
          topics.each do |topic|
            haystack = "#{topic.title} #{first_posts[topic.id]}".downcase
            score[topic.id] = words.count { |word| haystack.include?(word) }
          end
          topics = topics.select { |topic| score[topic.id].to_i > 0 || reported[topic.id] }
        end

        if (days = arguments["inactive_days"].to_i) > 0
          cutoff = days.days.ago
          topics = topics.select { |topic| (topic.bumped_at || topic.created_at) < cutoff }
        end

        limit = arguments.fetch("max_results", 10).to_i
        topics =
          if arguments["sort"] == "oldest"
            topics.sort_by { |topic| (topic.bumped_at || topic.created_at).to_f }
          else
            topics.sort_by do |topic|
              [
                reported[topic.id] ? 0 : 1,
                -score[topic.id].to_i,
                -(reported[topic.id] || topic.bumped_at || topic.created_at).to_f,
              ]
            end
          end
        shown = topics.first(limit)
        last_posters =
          User.where(id: shown.map(&:last_post_user_id).compact.uniq).index_by(&:id)
        Tools.result(
          tasks:
            shown.map do |topic|
              last_poster = last_posters[topic.last_post_user_id]
              {
                topic_id: topic.id,
                title: topic.title,
                category: topic.category&.name,
                last_activity: topic.bumped_at&.to_date&.iso8601,
                posts_count: topic.posts_count,
                my_last_post: my_last_post[topic.id]&.to_date&.iso8601,
                last_poster: last_poster&.username,
                waiting_on_it: last_poster.present? && !Tools.it_member?(last_poster),
                recently_reported: reported.key?(topic.id),
                url: "#{Discourse.base_url}#{topic.relative_url}",
              }
            end,
          total_open: ids.size,
          matching: topics.size,
        )
      end
    end

    module TaskContext
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic: DiscourseMcp::OutputSchema::OBJECT,
          first_post: DiscourseMcp::OutputSchema::OBJECT,
          last_posts: DiscourseMcp::OutputSchema::OBJECT_ARRAY,
        )

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        topic = Tools.find_assigned_topic!(arguments.fetch("topic_id"), request_context)
        posts = topic.posts.secured(request_context.guardian).where(deleted_at: nil)
        first = posts.find_by(post_number: 1)
        last_count = arguments.fetch("last_posts", 5).to_i
        last =
          posts.where.not(post_number: 1).order(post_number: :desc).limit(last_count).to_a.reverse
        row = ->(post, limit) do
          {
            post_number: post.post_number,
            username: post.username,
            created_at: post.created_at.iso8601,
            raw: Tools.truncate(post.raw, limit),
          }
        end
        Tools.result(
          topic: {
            id: topic.id,
            title: topic.title,
            category: topic.category&.name,
            url: "#{Discourse.base_url}#{topic.relative_url}",
            posts_count: topic.posts_count,
            closed: topic.closed,
            solved: Tools.solved?(topic),
          },
          first_post: first ? row.call(first, 8_000) : {},
          last_posts: last.map { |post| row.call(post, 4_000) },
        )
      end
    end

    module TaskReply
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_WRITE].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic_id: DiscourseMcp::OutputSchema::INTEGER,
          post_number: DiscourseMcp::OutputSchema::INTEGER,
          url: DiscourseMcp::OutputSchema::STRING,
          username: DiscourseMcp::OutputSchema::STRING,
          erp_time_url: DiscourseMcp::OutputSchema::STRING_OR_NULL,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        topic = Tools.find_assigned_topic!(arguments.fetch("topic_id"), request_context)
        if (topic.closed || Tools.solved?(topic)) && !arguments["confirm_closed"]
          state = topic.closed ? "zatvorena" : "označena kao riješena"
          raise DiscourseMcp::ToolError,
                "Tema ##{topic.id} je #{state}. Pitaj korisnika da li ipak želi javiti; ako da, pozovi ponovo sa confirm_closed=true."
        end
        SecretScanner.ensure_clean!(arguments.fetch("raw"))
        post = Tools.create_post!(user, topic_id: topic.id, raw: arguments.fetch("raw"))
        post.custom_fields[REPORTED_FIELD] = arguments.fetch("kind")
        post.save_custom_fields
        Tools.result(
          topic_id: post.topic_id,
          post_number: post.post_number,
          url: post.full_url,
          username: post.user.username,
          erp_time_url: Tools.erp_time_url(post, user),
        )
      end
    end

    module TaskSolve
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_WRITE].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic_id: DiscourseMcp::OutputSchema::INTEGER,
          post_number: DiscourseMcp::OutputSchema::INTEGER,
          url: DiscourseMcp::OutputSchema::STRING,
          erp_time_url: DiscourseMcp::OutputSchema::STRING_OR_NULL,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        topic = Tools.find_assigned_topic!(arguments.fetch("topic_id"), request_context)
        if !defined?(::DiscourseSolved)
          raise DiscourseMcp::ToolError, "Plugin discourse-solved nije uključen."
        end
        if Tools.solved?(topic)
          raise DiscourseMcp::ToolError, "Tema ##{topic.id} je već označena kao riješena."
        end

        posts = topic.posts.secured(request_context.guardian).where(deleted_at: nil)
        post =
          if arguments["post_number"].present?
            posts.find_by(post_number: arguments["post_number"].to_i)
          else
            posts.where(user_id: user.id).where.not(post_number: 1).order(post_number: :desc).first
          end
        if post.blank?
          raise DiscourseMcp::ToolError,
                "Nema posta za rješenje. Navedi post_number (tvoj zadnji post u temi nije pronađen)."
        end
        if post.post_number == 1
          raise DiscourseMcp::ToolError, "Prvi post (zadatak) ne može biti rješenje; navedi odgovor."
        end
        if !request_context.guardian.can_accept_answer?(topic, post)
          raise DiscourseMcp::ToolError, "Nemaš pravo označiti rješenje u ovoj temi."
        end

        outcome = ::DiscourseSolved.accept_answer!(post, user, topic: topic)
        if outcome.respond_to?(:failure?) && outcome.failure?
          raise DiscourseMcp::ToolError, "Označavanje rješenja nije uspjelo."
        end
        Tools.result(
          topic_id: topic.id,
          post_number: post.post_number,
          url: post.full_url,
          erp_time_url: Tools.erp_time_url(post, user),
        )
      end
    end

    module TaskClose
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_WRITE].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic_id: DiscourseMcp::OutputSchema::INTEGER,
          closed: DiscourseMcp::OutputSchema::BOOLEAN,
          note_url: DiscourseMcp::OutputSchema::STRING_OR_NULL,
          url: DiscourseMcp::OutputSchema::STRING,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        topic = Tools.find_assigned_topic!(arguments.fetch("topic_id"), request_context)
        Tools.ensure_confirmed!(arguments, "Zatvaranje teme")
        raise DiscourseMcp::ToolError, "Tema ##{topic.id} je već zatvorena." if topic.closed
        if !request_context.guardian.can_close_topic?(topic)
          raise DiscourseMcp::ToolError, "Nemaš pravo zatvoriti temu ##{topic.id}."
        end
        SecretScanner.ensure_clean!(arguments["raw"]) if arguments["raw"].present?

        note = Tools.create_note!(user, topic, arguments["raw"], "close")
        topic.update_status("closed", true, user)
        Tools.result(
          topic_id: topic.id,
          closed: topic.reload.closed,
          note_url: note&.full_url,
          url: "#{Discourse.base_url}#{topic.relative_url}",
        )
      end
    end

    module TaskReassign
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_WRITE].freeze
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topic_id: DiscourseMcp::OutputSchema::INTEGER,
          assigned_to: DiscourseMcp::OutputSchema::STRING,
          note_url: DiscourseMcp::OutputSchema::STRING_OR_NULL,
          url: DiscourseMcp::OutputSchema::STRING,
        )

      def self.call(arguments:, request_context:)
        user = Tools.ensure_member!(request_context)
        topic = Tools.find_assigned_topic!(arguments.fetch("topic_id"), request_context)
        Tools.ensure_confirmed!(arguments, "Prebacivanje teme")

        target = User.find_by_username(arguments.fetch("username").to_s.delete_prefix("@"))
        if !Tools.it_member?(target)
          colleagues =
            User
              .joins(:group_users)
              .where(group_users: { group_id: SiteSetting.robot_mcp_allowed_groups_map })
              .where.not(id: user.id)
              .distinct
              .pluck(:username)
          raise DiscourseMcp::ToolError,
                "Temu možeš prebaciti samo kolegi iz IT tima: #{colleagues.sort.join(", ")}."
        end
        raise DiscourseMcp::ToolError, "Tema je već dodijeljena tebi." if target.id == user.id
        SecretScanner.ensure_clean!(arguments["raw"]) if arguments["raw"].present?

        assignment = ::Assigner.new(topic, user).assign(target)
        if !assignment[:success]
          raise DiscourseMcp::ToolError,
                "Prebacivanje nije uspjelo (#{assignment[:reason] || "nepoznat razlog"})."
        end
        note = Tools.create_note!(user, topic, arguments["raw"], "reassign")
        Tools.result(
          topic_id: topic.id,
          assigned_to: target.username,
          note_url: note&.full_url,
          url: "#{Discourse.base_url}#{topic.relative_url}",
        )
      end
    end

    module CleanupPrompt
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        text = CLEANUP_INSTRUCTIONS
        text += "\nNapomena korisnika: #{arguments["opis"]}\n" if arguments["opis"].present?
        {
          description: "Očisti stare obaveze",
          messages: [{ role: "user", content: { type: "text", text: text } }],
        }
      end
    end

    module ReportPrompt
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        text = REPORT_INSTRUCTIONS
        text += "\nŠta treba javiti: #{arguments["opis"]}\n" if arguments["opis"].present?
        {
          description: "Javi ovo na forum",
          messages: [{ role: "user", content: { type: "text", text: text } }],
        }
      end
    end

    module DocumentPrompt
      REQUIRED_SCOPES = [DiscourseMcp::Scopes::CONTENT_READ].freeze

      def self.call(arguments:, request_context:)
        Tools.ensure_member!(request_context)
        text = DOCUMENT_INSTRUCTIONS
        text += "\nŠta treba dokumentovati: #{arguments["opis"]}\n" if arguments["opis"].present?
        {
          description: "Dokumentuj u IT-Wiki",
          messages: [{ role: "user", content: { type: "text", text: text } }],
        }
      end
    end
  end
end
