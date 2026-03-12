/**
 * TigrisUpload — Phoenix LiveView hook for direct-to-Tigris CSV uploads.
 *
 * Attach to a container with:
 *   phx-hook="TigrisUpload"
 *   data-upload-type="mde"          (or entity_master, enrollment, sat)
 *   data-accept=".csv"
 *
 * Inside the container, mark elements with data attributes:
 *   data-drop-zone        — drag-and-drop target area
 *   data-file-input       — <input type="file">
 *   data-import-btn       — button that triggers upload
 *   data-cancel-btn       — button that clears the selection
 */
const TigrisUpload = {
  mounted() {
    this.file = null
    this.uploadType = this.el.dataset.uploadType

    this.fileInput = this.el.querySelector("[data-file-input]")
    this.dropZone = this.el.querySelector("[data-drop-zone]")

    if (this.fileInput) {
      this.fileInput.addEventListener("change", e => {
        const f = e.target.files[0]
        if (f) this.setFile(f)
      })
    }

    if (this.dropZone) {
      this.dropZone.addEventListener("dragover", e => {
        e.preventDefault()
        this.dropZone.classList.add("border-warning")
      })
      this.dropZone.addEventListener("dragleave", () => {
        this.dropZone.classList.remove("border-warning")
      })
      this.dropZone.addEventListener("drop", e => {
        e.preventDefault()
        this.dropZone.classList.remove("border-warning")
        const f = e.dataTransfer.files[0]
        if (f) this.setFile(f)
      })
    }

    const importBtn = this.el.querySelector("[data-import-btn]")
    if (importBtn) {
      importBtn.addEventListener("click", () => this.startUpload())
    }

    const cancelBtn = this.el.querySelector("[data-cancel-btn]")
    if (cancelBtn) {
      cancelBtn.addEventListener("click", () => this.clearFile())
    }

    // Server sends presigned URL back
    this.handleEvent(`presigned_url:${this.uploadType}`, ({ url, key }) => {
      this.doUpload(url, key)
    })
  },

  setFile(file) {
    this.file = file
    if (this.fileInput) this.fileInput.value = ""
    this.pushEvent("file_selected", {
      upload_type: this.uploadType,
      name: file.name,
      size: file.size
    })
  },

  clearFile() {
    this.file = null
    if (this.fileInput) this.fileInput.value = ""
    this.pushEvent("file_cleared", { upload_type: this.uploadType })
  },

  startUpload() {
    if (!this.file) return
    this.pushEvent("request_upload_url", {
      upload_type: this.uploadType,
      filename: this.file.name,
      size: this.file.size
    })
  },

  doUpload(url, key) {
    const xhr = new XMLHttpRequest()
    xhr.open("PUT", url)
    xhr.setRequestHeader("Content-Type", "text/csv")

    xhr.upload.addEventListener("progress", e => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100)
        this.pushEvent("upload_progress", { upload_type: this.uploadType, progress: pct })
      }
    })

    xhr.addEventListener("load", () => {
      if (xhr.status === 200 || xhr.status === 204) {
        this.pushEvent("upload_complete", {
          upload_type: this.uploadType,
          key,
          filename: this.file.name
        })
        this.clearFile()
      } else {
        this.pushEvent("upload_failed", {
          upload_type: this.uploadType,
          reason: `Upload to storage failed (HTTP ${xhr.status})`
        })
      }
    })

    xhr.addEventListener("error", () => {
      this.pushEvent("upload_failed", {
        upload_type: this.uploadType,
        reason: "Network error during upload"
      })
    })

    xhr.send(this.file)
  }
}

export default TigrisUpload
