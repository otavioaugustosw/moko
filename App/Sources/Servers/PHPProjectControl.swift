import Foundation

extension PHPServer {
    func requestSwitch(to project: PHPProject) {
        guard !busy else { return }
        if !project.available {
            projectPrompt = .init(project: project, kind: .missingFolder)
        } else if project.id != projects.activeID || project.path != documentRoot {
            projectPrompt = .init(project: project, kind: .switchProject)
        }
    }
    func confirmSwitch(to project: PHPProject, connection: DatabaseConnection?) {
        guard !busy, project.available else {
            projectPrompt = .init(project: project, kind: .missingFolder)
            return
        }
        projectPrompt = nil
        let restart = running
        let apply = {
            self.projects.activate(project)
            self.documentRoot = project.path
            self.port = project.port
            self.router = project.router
            self.saveConfiguration()
            if restart { self.start(connection: connection) }
        }
        if restart { stop(completed: apply) } else { apply() }
    }
    func registerInitialProject(_ url: URL, port: String) {
        let project = projects.add(url, port: port)
        if projects.activeID == nil && !running {
            confirmSwitch(to: project, connection: nil)
        } else {
            requestSwitch(to: project)
        }
    }
    func requestRemoval(_ project: PHPProject) {
        guard !busy else { return }
        projectPrompt = .init(project: project, kind: .removeProject)
    }
    func removeProject(_ project: PHPProject) {
        guard !busy else { return }
        projectPrompt = nil
        let active = projects.activeID == project.id
        let apply = {
            self.projects.remove(project)
            if active {
                self.documentRoot = ""
                self.router = ""
                self.saveConfiguration()
            }
        }
        if active && running { stop(completed: apply) } else { apply() }
    }
    func updateFolder(for project: PHPProject, to url: URL) {
        var updated = project
        updated.path = url.standardizedFileURL.path
        projects.update(updated)
        projectPrompt = nil
        requestSwitch(to: updated)
    }
    func saveConfiguration() {
        if var project = projects.active, project.path == documentRoot {
            project.port = port
            project.router = router
            projects.update(project)
        }
        guard !PreviewRuntime.isActive else { return }
        preferences.set(documentRoot, forKey: "moko.php.root")
        preferences.set(port, forKey: "moko.php.port")
    }
}
