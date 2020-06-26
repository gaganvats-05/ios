//
//  DownloadsGridCollectionCell.swift
//  AmahiAnywhere
//
//  Created by Marton Zeisler on 2019. 06. 27..
//  Copyright © 2019. Amahi. All rights reserved.
//

import UIKit

class DownloadsGridCollectionCell: DownloadsBaseCollectionCell{
    
    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var moreButton: UIButton!
    @IBOutlet weak var brokenIndicatorImageView: UIImageView!
    @IBOutlet weak var progressView: UIProgressView!
    
    func setupData(offlineFile: OfflineFile){
        nameLabel.text = offlineFile.name
        
        let image = brokenIndicatorImageView.image
        let templateImage = image?.withRenderingMode(.alwaysTemplate)
        brokenIndicatorImageView.image = templateImage
        brokenIndicatorImageView.tintColor = UIColor.brokenIndicatorRed
        
        if #available(iOS 13.0, *) {
            nameLabel.textColor = UIColor.label
            moreButton.tintColor = UIColor.label
        } else {
            nameLabel.textColor = UIColor.white
            moreButton.tintColor = UIColor.white
        }
        
        setupProgressView(offlineFile: offlineFile, progressView: progressView)
        
        if offlineFile.stateEnum == .downloading {
            if let remoteUrl = offlineFile.remoteFileURL() {
                let keyExists = DownloadService.shared.activeDownloads[remoteUrl] != nil
                if !keyExists {
                    offlineFile.stateEnum = .completedWithError
                }
            }
        }
        
        if offlineFile.stateEnum == .completedWithError {
            brokenIndicatorImageView.isHidden = false
        } else {
            brokenIndicatorImageView.isHidden = true
        }
        
        setupArtWork(offlineFile: offlineFile, iconImageView: iconImageView)
    }
    
    func updateProgress(offlineFile: OfflineFile){
        updateProgress(offlineFile: offlineFile, progressView: progressView, brokenIndicator: brokenIndicatorImageView, iconImageView: iconImageView)
    }
}
