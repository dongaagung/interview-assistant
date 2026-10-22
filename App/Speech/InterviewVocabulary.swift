import Foundation

/// Terms the recognizer should expect in a tech interview. They go to
/// SpeechAnalyzer as contextual strings, so "Kafka" isn't heard as "cough".
enum InterviewVocabulary {
    /// Speech models get no documented limit; past a few hundred, biasing
    /// toward rare terms starts to cost accuracy on ordinary words.
    static let limit = 500

    /// The candidate's own terms first (the most specific), then terms they
    /// added by hand, then the built-in lists. Deduplicated, case-insensitive.
    static func contextualStrings(
        profile: Profile, stories: [StarStory], extra: [String], limit: Int = limit
    ) -> [String] {
        deduplicated(terms(from: profile, stories: stories) + extra + builtIn)
            .prefix(limit).map { $0 }
    }

    static func terms(from profile: Profile, stories: [StarStory]) -> [String] {
        var terms: [String] = []
        if !profile.targetCompany.isEmpty { terms.append(profile.targetCompany) }
        terms += stories.flatMap(\.tags)
        let texts = [profile.targetRole, profile.background, profile.jobDescription, profile.resume]
            + stories.flatMap { [$0.title, $0.situation, $0.task, $0.action, $0.result] }
        terms += texts.flatMap(extractTerms(from:))
        return deduplicated(terms)
    }

    /// Picks out words that look like names of technologies, products or
    /// companies: PostgreSQL, gRPC, AWS, K8s, Node.js, C++, or a capitalized
    /// word mid-sentence that isn't an ordinary English word (Kafka, Mandiri).
    static func extractTerms(from text: String) -> [String] {
        var terms: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            // Lines, bullets and "|"-separated parts each start like a sentence.
            var atSentenceStart = true
            for raw in line.split(whereSeparator: \.isWhitespace) {
                defer { atSentenceStart = raw.last.map { ".!?:•|–-".contains($0) } ?? false }
                var token = raw.trimmingCharacters(in: edgePunctuation)
                for suffix in ["'s", "’s"] where token.hasSuffix(suffix) {
                    token = String(token.dropLast(suffix.count))
                }
                guard token.count >= 2, token.contains(where: \.isLetter), !isWebAddress(token) else { continue }
                // CV headings ("PROFESSIONAL", "EXPERIENCE") aren't terms; acronyms are short.
                if token.count > 6, token.allSatisfy(\.isUppercase) { continue }
                let hasInnerUppercase = token.dropFirst().contains(where: \.isUppercase)
                let mixesDigits = token.contains(where: \.isNumber)
                // Node.js, Vert.x, C++, C#; not e.g. or i.e.
                let hasSymbol = token.contains { "+#".contains($0) }
                    || (token.contains(".") && token.split(separator: ".").contains { $0.count >= 2 })
                let isProperNoun = token.first!.isUppercase && !atSentenceStart && token.count >= 3
                    && !commonCapitalizedWords.contains(token.lowercased())
                    && !englishWords.contains(token.lowercased())
                if hasInnerUppercase || mixesDigits || hasSymbol || isProperNoun {
                    terms.append(token)
                }
            }
        }
        return terms
    }

    private static func isWebAddress(_ token: String) -> Bool {
        token.contains("/") || token.contains("@")
            || [".com", ".org", ".net", ".io", ".id", ".co"].contains { token.lowercased().hasSuffix($0) }
    }

    /// Lowercase entries of the system word list: ordinary English words,
    /// which a capital letter alone ("Senior Software Engineer") doesn't make
    /// into terms. Proper nouns in the list are capitalized, so they're kept.
    private static let englishWords: Set<String> = {
        guard let words = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(words.split(separator: "\n").filter { $0.first?.isLowercase ?? false }.map(String.init))
    }()

    static func deduplicated(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    /// Strips punctuation around a word, but keeps C++ and C# intact.
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?()[]{}\"'“”‘’…/")
        .union(.whitespaces)

    private static let commonCapitalizedWords: Set<String> = [
        "the", "and", "but", "for", "our", "this", "that", "with", "when", "then", "also",
        "saya", "kami", "dan", "yang", "untuk", "dengan", "ini", "itu",
    ]

    static var builtIn: [String] { java + architecture + platform + practices }

    static let java = [
        "Java", "JVM", "JDK", "JRE", "JIT", "bytecode", "garbage collection", "G1GC", "ZGC",
        "heap", "metaspace", "classloader", "Java Flight Recorder", "GraalVM", "native image",
        "Kotlin", "Scala", "Maven", "Gradle",
        "Spring", "Spring Boot", "Spring MVC", "Spring WebFlux", "Spring Cloud", "Spring Security",
        "Spring Data", "Spring Batch", "Spring Cloud Gateway", "Actuator", "Micrometer",
        "Hibernate", "JPA", "JDBC", "jOOQ", "MyBatis", "HikariCP", "Flyway", "Liquibase",
        "Lombok", "Jackson", "JUnit", "Mockito", "AssertJ", "Testcontainers",
        "Quarkus", "Micronaut", "Vert.x", "Netty", "Tomcat", "Jetty", "Jakarta EE", "servlet",
        "dependency injection", "inversion of control", "bean", "annotation", "Autowired",
        "CompletableFuture", "ExecutorService", "thread pool", "virtual threads", "Project Loom",
        "Project Reactor", "RxJava", "reactive streams", "Mono", "Flux",
        "Optional", "stream API", "lambda", "functional interface", "generics", "records",
        "sealed classes", "pattern matching", "synchronized", "volatile", "ReentrantLock",
        "ConcurrentHashMap", "HashMap", "ArrayList", "immutable", "deadlock", "race condition",
        "memory leak", "OutOfMemoryError", "NullPointerException", "checked exception",
        "try-with-resources", "serialization", "reflection", "Log4j", "SLF4J", "Logback",
        "Resilience4j", "Hystrix", "OpenFeign", "Eureka",
    ]

    static let architecture = [
        "microservices", "monolith", "modular monolith", "service mesh", "Istio", "Envoy",
        "API gateway", "load balancer", "reverse proxy", "circuit breaker", "bulkhead",
        "retry with backoff", "exponential backoff", "rate limiting", "throttling", "idempotency",
        "idempotent", "eventual consistency", "strong consistency", "CAP theorem", "ACID",
        "distributed transaction", "two-phase commit", "saga pattern", "choreography", "orchestration",
        "outbox pattern", "transactional outbox", "change data capture", "CDC", "Debezium",
        "event sourcing", "CQRS", "domain-driven design", "DDD", "bounded context", "aggregate",
        "value object", "hexagonal architecture", "ports and adapters", "clean architecture",
        "layered architecture", "event-driven architecture", "pub/sub", "message broker",
        "message queue", "dead letter queue", "DLQ",
        "Kafka", "Apache Kafka", "Kafka Streams", "Kafka Connect", "partition", "consumer group",
        "offset", "topic", "ZooKeeper", "KRaft", "RabbitMQ", "ActiveMQ", "Pulsar", "NATS",
        "SQS", "SNS", "Kinesis", "exactly-once", "at-least-once", "backpressure",
        "sharding", "replication", "leader election", "consensus", "Raft", "Paxos", "quorum",
        "read replica", "horizontal scaling", "vertical scaling", "autoscaling",
        "high availability", "fault tolerance", "disaster recovery", "failover",
        "single point of failure", "SLA", "SLO", "SLI", "latency", "throughput", "p99",
        "caching", "cache invalidation", "cache-aside", "write-through", "Redis", "Memcached",
        "Hazelcast", "CDN", "consistent hashing", "bloom filter",
        "REST", "RESTful", "gRPC", "GraphQL", "WebSocket", "protobuf", "Avro", "OpenAPI", "Swagger",
        "OAuth", "OAuth2", "OpenID Connect", "JWT", "SSO", "mTLS", "RBAC", "Keycloak",
        "API versioning", "backward compatibility", "system design", "scalability", "bottleneck",
        "trade-off",
    ]

    static let platform = [
        "PostgreSQL", "Postgres", "MySQL", "Oracle", "SQL Server", "MongoDB", "Cassandra",
        "DynamoDB", "Elasticsearch", "ClickHouse", "NoSQL", "SQL", "index", "B-tree",
        "query plan", "N+1 query", "connection pool", "optimistic locking", "pessimistic locking",
        "isolation level", "read committed", "repeatable read", "normalization", "denormalization",
        "ORM", "database migration", "ETL", "data pipeline", "Spark", "Flink", "Airflow",
        "Docker", "container", "Kubernetes", "K8s", "Helm", "pod", "sidecar", "Terraform",
        "Ansible", "infrastructure as code", "AWS", "Azure", "GCP", "EC2", "S3", "AWS Lambda",
        "serverless", "EKS", "RDS", "CloudWatch", "VPC",
        "CI/CD", "Jenkins", "GitHub Actions", "GitLab CI", "Argo CD", "GitOps",
        "blue-green deployment", "canary release", "feature flag", "rolling update",
        "observability", "distributed tracing", "OpenTelemetry", "Jaeger", "Zipkin", "Prometheus",
        "Grafana", "ELK stack", "Kibana", "Datadog", "New Relic",
    ]

    static let practices = [
        "SOLID", "single responsibility", "open-closed principle", "Liskov substitution",
        "interface segregation", "dependency inversion", "DRY", "KISS", "YAGNI",
        "design patterns", "singleton", "factory", "builder pattern", "strategy pattern",
        "observer pattern", "adapter", "decorator", "facade", "proxy",
        "technical debt", "refactoring", "code review", "unit test", "integration test",
        "end-to-end test", "TDD", "BDD", "mocking", "test coverage", "SonarQube",
        "Agile", "Scrum", "Kanban", "sprint", "retrospective", "story points", "Jira",
        "Git", "pull request", "merge request", "rebase", "trunk-based development",
        "Big O", "time complexity", "space complexity", "hash table", "binary search",
        "linked list", "binary tree", "graph", "dynamic programming", "recursion",
        "postmortem", "incident", "on-call", "root cause analysis", "stakeholder",
    ]
}
