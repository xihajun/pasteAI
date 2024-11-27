import Foundation
import AppKit

class ReminderService: ObservableObject {
    static let shared = ReminderService()
    
    private init() {}
    
    func addReminder(content: String) {
        let reminderTitle = "remind from paste"
        let reminderNote = content

        // Combine as a single string for sharing (title + note)
        let reminderItem = "\(reminderTitle)\n\(reminderNote)"
        
        // Get sharing services for the item
        let sharingServices = NSSharingService.sharingServices(forItems: [reminderItem as NSString])
        
        // Find the Reminders service
        if let reminderService = sharingServices.first(where: { $0.title.contains("Reminders") }) {
            print("Found Reminders service")
            // Perform the action
            reminderService.perform(withItems: [reminderItem])
        } else {
            print("Reminders service not available in services: \(sharingServices.map { $0.title })")
        }
    }

    func addReminderWithAppleScript(title: String, note: String) {
        let appleScript = """
        tell application "Reminders"
            set newReminder to make new reminder
            set name of newReminder to "\(title)"
            set body of newReminder to "\(note)"
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: appleScript) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript Error: \(error)")
            } else {
                print("Reminder added successfully!")
            }
        }
    }

}
