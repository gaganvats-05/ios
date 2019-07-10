//
//  FilesTableViewController.swift
//  AmahiAnywhere
//
//  Created by Chirag Maheshwari on 08/03/18.
//  Copyright © 2018 Amahi. All rights reserved.
//

import UIKit
import Lightbox
import AVFoundation
import GoogleCast

class FilesViewController: BaseUIViewController, GCKSessionManagerListener,
GCKRemoteMediaClientListener, GCKRequestDelegate {
    
    enum PlaybackMode: Int {
        case none = 0
        case local
        case remote
    }
    
    var mediaInfo: GCKMediaInformation? {
        didSet {
            print("setMediaInfo: \(String(describing: mediaInfo))")
        }
    }
    
    public var sessionManager: GCKSessionManager!
    public var mediaInformation: GCKMediaInformation?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        sessionManager = GCKCastContext.sharedInstance().sessionManager
    }
    
    public var playbackMode = PlaybackMode.none
    
    // Mark - Server properties, will be set from presenting class
    public var directory: ServerFile?
    public var share: ServerShare!
    
    private var castButton: GCKUICastButton!
    
    // Mark - TableView data properties
    internal var serverFiles = [ServerFile]()
    internal var filteredFiles = FilteredServerFiles()
    
    internal var fileSort: FileSort!
    
    /*
     KVO context used to differentiate KVO callbacks for this class versus other
     classes in its class hierarchy.
     */
    internal var playerKVOContext = 0
    
    // Mark - UIKit properties
    internal var refreshControl: UIRefreshControl!
    internal var downloadProgressAlertController : UIAlertController?
    internal var progressView: UIProgressView?
    internal var docController: UIDocumentInteractionController?
    
    @objc internal var player: AVPlayer!
    
    internal var isAlertShowing = false
    internal var presenter: FilesPresenter!
    
    @IBOutlet var filesCollectionView: UICollectionView!
    var searchController: UISearchController!
    var sortView: SortView!
    var sortBackgroundView: UIView!
    
    @IBOutlet var sortButton: UIButton!
    @IBOutlet var layoutButton: UIButton!
    var layoutView: LayoutView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        presenter = FilesPresenter(self)
        setupLayoutView()
        setupRefreshControl()
        setupNavigationItem()
        setupSearchBar()
        setupCollectionView()
        updateFileSort(sortingMethod: GlobalFileSort.fileSort)
        presenter.getFiles(share, directory: directory)
        
        castButton = GCKUICastButton(frame: CGRect(x: CGFloat(0), y: CGFloat(0),
                                                   width: CGFloat(24), height: CGFloat(24)))
        castButton.tintColor = UIColor.white
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: castButton)
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(castDeviceDidChange),
                                               name: NSNotification.Name.gckCastStateDidChange,
                                               object: GCKCastContext.sharedInstance())
    }
    
    @objc func castDeviceDidChange(_: Notification) {
        if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
            // You can present the instructions on how to use Google Cast on
            // the first time the user uses you app
            GCKCastContext.sharedInstance().presentCastInstructionsViewControllerOnce(with: castButton)
        }
    }
    
    func setupLayoutView(){
        layoutView = GlobalLayoutView.layoutView
        
        if layoutView == .listView{
            layoutButton.setImage(UIImage(named: "filesGridIcon"), for: .normal)
        }else{
            layoutButton.setImage(UIImage(named: "filesListIcon"), for: .normal)
        }
    }
    
    func setupRefreshControl(){
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.attributedTitle = NSAttributedString(string: "Pull to Refresh", attributes: [.foregroundColor: UIColor.white])
        self.refreshControl?.addTarget(self, action: #selector(handleRefresh), for: UIControl.Event.valueChanged)
        filesCollectionView.addSubview(refreshControl)
    }
    
    func setupNavigationItem(){
        self.navigationItem.title = getTitle()
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: getTitle(), style: .plain, target: nil, action: nil)
    }
    
    func setupCollectionView(){
        filesCollectionView.delegate = self
        filesCollectionView.dataSource = self
        filesCollectionView.allowsMultipleSelection = false
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        filesCollectionView.addGestureRecognizer(longPressGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if fileSort != GlobalFileSort.fileSort || layoutView != GlobalLayoutView.layoutView{
            setupLayoutView()
            updateFileSort(sortingMethod: GlobalFileSort.fileSort, refreshCollectionView: true)
        }
        
        presenter.loadOfflineFiles()
        let hasConnectedSession: Bool = (sessionManager.hasConnectedSession())
        if hasConnectedSession, (playbackMode != .remote) {
            
        } else if sessionManager.currentSession == nil, (playbackMode != .local) {
        }
        sessionManager.add(self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(offlineFileUpdated), name: .DownloadCompletedSuccessfully, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(offlineFileUpdated), name: .OfflineFileDeleted, object: nil)
    }
    
    @objc func offlineFileUpdated(_ notification: Notification){
        
        if notification.userInfo?["loadOfflineFiles"] != nil{
            presenter.loadOfflineFiles()
        }
        
        if let offlineFile = notification.object as? OfflineFile, let indexPath = OfflineFileIndexes.offlineFilesIndexPaths[offlineFile] {
            if indexPath.section < filesCollectionView.numberOfSections && indexPath.item < filesCollectionView.numberOfItems(inSection: indexPath.section){
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.filesCollectionView.reloadItems(at: [indexPath])
                }
            }
        }
    }
    
    func setupSearchBar(){
        let searchButton = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(searchTapped))
        self.navigationItem.rightBarButtonItem = searchButton
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"
        searchController.searchBar.tintColor = .white
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).defaultTextAttributes = [.foregroundColor: UIColor.white]
        searchController.delegate = self
        searchController.searchBar.delegate = self
        
        definesPresentationContext = true
        navigationController?.view.backgroundColor = self.view.backgroundColor
    }
    
    @objc func searchTapped(){
        self.navigationItem.searchController = searchController
        self.navigationItem.hidesSearchBarWhenScrolling = false
        searchController.isActive = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchController.searchBar.resignFirstResponder()
        sessionManager.remove(self)
    }
    
    @objc func moreButtonTapped(sender: UIButton){
        let bounds = sender.convert(sender.bounds, to: filesCollectionView)
        handleMoreMenu(touchPoint: bounds.origin)
    }
    
    func handleMoreMenu(touchPoint: CGPoint){
        if let indexPath = filesCollectionView.indexPathForItem(at: touchPoint) {
            
            let file = self.filteredFiles.getFileFromIndexPath(indexPath)
            
            if file.isDirectory { return }
            
            let download = self.creatAlertAction(StringLiterals.download, style: .default) { (action) in
                self.presenter.makeFileAvailableOffline(file, indexPath)
                }!
            let state = presenter.checkFileOfflineState(file)
            
            let share = self.creatAlertAction(StringLiterals.share, style: .default) { (action) in
                self.presenter.shareFile(file, fileIndex: indexPath.row, section: indexPath.section,
                                         from: self.filesCollectionView.cellForItem(at: indexPath))
                }!
            
            let removeOffline = self.creatAlertAction(StringLiterals.removeOfflineMessage, style: .default) { (action) in
                }!
            
            let stop = self.creatAlertAction(StringLiterals.stopDownload, style: .default) { (action) in
                }!
            
            var actions = [UIAlertAction]()
            actions.append(share)
            
            if state == .none {
                actions.append(download)
            } else if state == .downloaded {
                actions.append(removeOffline)
            } else if state == .downloading {
                actions.append(stop)
            }
            
            let cancel = self.creatAlertAction(StringLiterals.cancel, style: .cancel, clicked: nil)!
            actions.append(cancel)
            
            self.createActionSheet(title: file.name,
                                   message: nil,
                                   ltrActions: actions,
                                   preferredActionPosition: 0,
                                   sender: filesCollectionView.cellForItem(at: indexPath))
        }
    }
    
    @objc func handleLongPress(sender: UIGestureRecognizer) {
        handleMoreMenu(touchPoint: sender.location(in: filesCollectionView))
    }
    
    @objc func userClickMenu(sender: UIGestureRecognizer) {
        handleLongPress(sender: sender)
    }
    
    @objc func handleRefresh(sender: UIRefreshControl) {
        presenter.getFiles(share, directory: directory)
    }
    
    func getTitle() -> String? {
        if directory != nil {
            return directory!.name
        }
        return share!.name
    }
    
    internal func setupDownloadProgressIndicator() {
        downloadProgressAlertController = UIAlertController(title: "", message: "", preferredStyle: .alert)
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView?.setProgress(0.0, animated: true)
        progressView?.frame = CGRect(x: 10, y: 100, width: 250, height: 2)
        downloadProgressAlertController?.view.addSubview(progressView!)
        let height:NSLayoutConstraint = NSLayoutConstraint(item: downloadProgressAlertController!.view, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 1, constant: 120)
        downloadProgressAlertController?.view.addConstraint(height);
    }
    
    // MARK: - Navigation
    
    func handleFolderOpening(serverFile: ServerFile){
        let vc = UIStoryboard(name: StoryBoardIdentifiers.main, bundle: nil).instantiateViewController(withIdentifier: StoryBoardIdentifiers.filesViewController) as! FilesViewController
        vc.share = self.share
        vc.directory = serverFile
        vc.fileSort = fileSort
        vc.layoutView = layoutView
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    @IBAction func sortingTapped(_ sender: UIButton){
        showSortViews()
    }
    
    func showSortViews(){
        sortBackgroundView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        sortBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        sortBackgroundView.isHidden = true
        sortBackgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSortView)))
        
        let height = self.view.frame.height > self.view.frame.width ? self.view.frame.height * 0.4 : self.view.frame.width * 0.3
        sortView = SortView(frame: CGRect(x: 0, y: UIScreen.main.bounds.height, width: UIScreen.main.bounds.width, height: height))
        sortView.selectedFilter = self.fileSort
        sortView.sortViewDelegate = self
        sortView.tableView.reloadData()
        
        self.view.window?.addSubview(sortBackgroundView)
        self.view.window?.addSubview(sortView)
    
        UIView.animate(withDuration: 0.3) {
            self.sortBackgroundView.isHidden = false
            self.sortView.frame.origin.y = UIScreen.main.bounds.height - (height)
        }
    }
    
    @objc func dismissSortView(){
        UIView.animate(withDuration: 0.3, animations: {
            self.sortBackgroundView.isHidden = true
            self.sortView.frame.origin.y = UIScreen.main.bounds.height
        }) { (_) in
            self.sortBackgroundView.removeFromSuperview()
            self.sortView.removeFromSuperview()
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // Landscape to Portrait: width - > height, height -> width
        // Portrait to Landscape: width -> height, height -> width
        if sortBackgroundView != nil && sortView != nil{
            sortBackgroundView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.height, height: UIScreen.main.bounds.width)
            let height = size.height > size.width ? size.height * 0.4 : size.width * 0.3
            sortView.frame = CGRect(x: 0, y: UIScreen.main.bounds.width - height, width: size.width, height: height)
        }
    }
    
    @IBAction func layoutButtonTapped(_ sender: Any) {
        GlobalLayoutView.switchLayoutMode()
        setupLayoutView()
        filesCollectionView.reloadData()
    }
    
    func updateFileSort(sortingMethod: FileSort, refreshCollectionView: Bool = false){
        UIView.performWithoutAnimation {
            self.sortButton.setTitle(sortingMethod.rawValue, for: .normal)
            self.sortButton.layoutIfNeeded()
        }
        
        GlobalFileSort.fileSort = sortingMethod
        fileSort = sortingMethod
        
        if refreshCollectionView{
            updateFiles(serverFiles)
        }
    }
    
    // MARK: - GCKSessionManagerListener
    
    func sessionManager(_: GCKSessionManager, didStart session: GCKSession) {
        print("MediaViewController: sessionManager didStartSession \(session)")
        //setQueueButtonVisible(true)
        //switchToRemotePlayback()
    }
    
    func sessionManager(_: GCKSessionManager, didResumeSession session: GCKSession) {
        print("MediaViewController: sessionManager didResumeSession \(session)")
        //setQueueButtonVisible(true)
        //switchToRemotePlayback()
    }
    
    func sessionManager(_: GCKSessionManager, didEnd _: GCKSession, withError error: Error?) {
        print("session ended with error: \(String(describing: error))")
        let message = "The Casting session has ended.\n\(String(describing: error))"
        if let window = appDelegate!.window {
            Toast.displayMessage(message, for: 3, in: window)
        }
        //setQueueButtonVisible(false)
        //switchToLocalPlayback()
    }
    
    func sessionManager(_: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
        if let error = error {
            showAlert(withTitle: "Failed to start a session", message: error.localizedDescription)
        }
        //setQueueButtonVisible(false)
    }
    
    func showAlert(withTitle title: String, message: String) {
        let alert = UIAlertView(title: title,
                                message: message,
                                delegate: nil,
                                cancelButtonTitle: "OK",
                                otherButtonTitles: "")
        alert.show()
    }
    
    func sessionManager(_: GCKSessionManager,
                        didFailToResumeSession _: GCKSession, withError _: Error?) {
        if let window = UIApplication.shared.delegate?.window {
            Toast.displayMessage("The Casting session could not be resumed.",
                                 for: 3, in: window)
        }
        //setQueueButtonVisible(false)
        //switchToLocalPlayback()
    }
    
}

extension FilesViewController: SortViewDelegate{
    func sortingSelected(sortingMethod: FileSort) {
        dismissSortView()
        
        if sortingMethod == fileSort {
            return
        }
        
        updateFileSort(sortingMethod: sortingMethod, refreshCollectionView: true)
    }
}
