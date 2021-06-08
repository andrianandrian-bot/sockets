//
//  ViewController.swift
//  Sockets
//
//  Created by Andreas on 07.06.2021.
//

import UIKit

class ViewController: UIViewController {
    
    let connection = NetworkManager(host: "85.10.205.177", port: 2023)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        connection.writeStream()
        
        print(#function)
    }


}

