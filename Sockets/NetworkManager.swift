//
//  NetworkManager.swift
//  Sockets
//
//  Created by Andreas on 07.06.2021.
//

import Foundation
import SwiftProtobuf


final class NetworkManager: NSObject {

    private let host: String
    private let port: Int

    private var inputStream: InputStream! // swiftlint:disable:this implicitly_unwrapped_optional
    private var outputStream: OutputStream! // swiftlint:disable:this implicitly_unwrapped_optional
    private var observers: [NSObjectProtocol] = []

    init(host: String, port: Int) {
        self.host = host
        self.port = port
        super.init()
        openStreams()
        setupObservers()
    }
    
    func writeStream() {
        guard
            let wrapperMessage = try? makeWrapperMessage(with: makeSyncRequest()),
            var data = try? wrapperMessage.serializedData()
        else { return }
        data.insert(UInt8(data.count), at: 0)

        data.withUnsafeBytes {
            guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            outputStream.write(pointer, maxLength: data.count)
        }
    }
    
    func makeWrapperMessage(with message: Message) throws -> AutoControl_Messenger_WrapperMessage {
        try AutoControl_Messenger_WrapperMessage.with {
            $0.type = type(of: message)
            $0.data = try message.serializedData()
            $0.compressed = false
            $0.seq = 111
        }
    }
    
    private func type(of message: Message) -> AutoControl_Messenger_Type {
        if message is AutoControl_Messenger_SyncRequest {
            return .syncRequestType
        }
        if message is AutoControl_Messenger_SyncBusRequest {
            return .syncBusRequestType
        }
        if message is AutoControl_Messenger_SyncPointRequest {
            return .syncPointRequestType
        }

        assertionFailure()
        return .connectRequestType
    }
    
    func makeSyncRequest() -> Message {
        return AutoControl_Messenger_SyncRequest.with {
            $0.lastSyncTime = Int64(Date().timeIntervalSince1970)
        }
    }
        

    private func setupObservers() {
        let block: (Foundation.Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            switch UIApplication.shared.applicationState {
            case .background:
                self.closeStreams()
            case .active:
                self.openStreams()
            default:
                break
            }
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main,
                using: block
            ),
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
                using: block
            )
        ]
    }

    private func openStreams() {
        guard inputStream == nil, outputStream == nil else { return }
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inputStream, outputStream: &outputStream)

        inputStream.delegate = self

        inputStream.schedule(in: .main, forMode: .common)
        outputStream.schedule(in: .main, forMode: .common)

        inputStream.open()
        outputStream.open()

//        send(makeSyncRequest())
    }

    private func closeStreams() {
        guard inputStream != nil, outputStream != nil else { return }

        inputStream.delegate = nil

        inputStream.close()
        outputStream.close()

        inputStream.remove(from: .main, forMode: .common)
        outputStream.remove(from: .main, forMode: .common)

        inputStream = nil
        outputStream = nil
    }

    private func reconnectStreams() {
        closeStreams()
        openStreams()
    }
//
//    private func send(message: Message) {
//        guard
//            let wrapperMessage = try? messageFactory.makeWrapperMessage(with: message),
//            var data = try? wrapperMessage.serializedData()
//        else { return }
//        data.insert(UInt8(data.count), at: 0)
//
//        data.withUnsafeBytes {
//            guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
//            outputStream.write(pointer, maxLength: data.count)
//        }
//    }

    deinit {
        closeStreams()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

// MARK: - Stream Delegate

extension NetworkManager: StreamDelegate {
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let inputStream = inputStream else { return }
        print("Event code is ", eventCode)
        
        switch eventCode {
        case .hasBytesAvailable:
            // TODO: - Нужно для того, чтобы дождаться, пока все байты будут доступны
            // В противном случае, часто стреляет ошибка truncated(bytesRead != length),
            // что в свою очередь ведет к проблеме malformedProtobuf.
            // В последствии это ведет к крашу приложения
            // Необходимо придумать нормальное решение, а не надеятся, что через 0.25 секунды данные дойдут
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self else { return }
                while inputStream.hasBytesAvailable {
                    self.readWrapperMessage(from: inputStream)
                    print("success")
                }
            }
        case .errorOccurred:
            reconnectStreams()
            print("fail")
        case .endEncountered:
            print("endEncountered")
        case .openCompleted:
            print("openCompleted")
        default:
            print("default")
            break
        }
    }

    func readWrapperMessage(from inputStream: InputStream) {
        do {
            let wrapperMessage = try BinaryDelimited.parse(
                messageType: AutoControl_Messenger_WrapperMessage.self,
                from: inputStream
            )
            
            print("Type is ", wrapperMessage.type)

            switch wrapperMessage.type {
            case .syncRouteResponseType:
                print("syncRouteResponseType")
            default:
                print(wrapperMessage.type)
                break
            }
        } catch {
            reconnectStreams()
        }
    }
}
