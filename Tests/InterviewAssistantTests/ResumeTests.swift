import Foundation
import Testing
@testable import InterviewAssistant

struct ResumeTests {
    @Test func removesEmailAndPhoneButKeepsFigures() {
        let text = "+62 823 5012 5334 | dongaagung@gmail.com | 0812-3456-7890\nCut 13,508 ms to 3,552 ms; 2015 - 2019; GPA 3.84/4.00; 2,200+ branches"
        #expect(ResumeImport.redactContactDetails(text)
            == "[phone] | [email] | [phone]\nCut 13,508 ms to 3,552 ms; 2015 - 2019; GPA 3.84/4.00; 2,200+ branches")
    }

    @Test func importsPlainText() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cv-\(UUID().uuidString).txt")
        try "AGUNG\n\n\n\nJava   \nmail: a@b.co".write(to: url, atomically: true, encoding: .utf8)
        #expect(try ResumeImport.text(from: url) == "AGUNG\n\nJava\nmail: [email]")
    }

    @Test func olderProfileFileLoadsWithEmptyResume() throws {
        let old = #"{"name":"Agung","targetRole":"Senior Java Developer","background":"","jobDescription":"","targetCompany":"","answerLanguage":""}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        #expect(profile.name == "Agung")
        #expect(profile.resume.isEmpty)
    }

    @Test func resumeReachesPromptsAndVocabulary() {
        let profile = Profile(name: "Agung", resume: "Built the Warkat and BI-FAST modules for Bank Mandiri.\nPROFESSIONAL EXPERIENCE")
        #expect(PromptContext.profile(profile).hasSuffix("Resume (CV):\nBuilt the Warkat and BI-FAST modules for Bank Mandiri.\nPROFESSIONAL EXPERIENCE"))
        let terms = InterviewVocabulary.terms(from: profile, stories: [])
        #expect(terms.contains("BI-FAST") && terms.contains("Mandiri") && terms.contains("Warkat"))
        #expect(!terms.contains("PROFESSIONAL"))
    }
}
