//
//  RuntimeResponseWriter.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import Foundation

actor RuntimeResponseWriter {
    private let connection: any RuntimeConnection
    private var isSending = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    init(connection: any RuntimeConnection) {
        self.connection = connection
    }

    func send(_ data: Data) async throws {
        await acquire()
        defer { release() }
        try await connection.send(data)
    }

    private func acquire() async {
        guard isSending else {
            isSending = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isSending = false
            return
        }
        waiters.removeFirst().resume()
    }
}
