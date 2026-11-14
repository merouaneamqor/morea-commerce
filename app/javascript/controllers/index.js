// Register controllers when their markup is on the page, so the storefront
// does not download every admin controller before the first paint.
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
import VariantGalleryController from "controllers/variant_gallery_controller"
import VariantPickerController from "controllers/variant_picker_controller"

// Color gallery and picker must be present before the first swatch click. Lazy
// loading them separately was still dropping the picker's first change when the
// gallery module arrived late, even after sync-on-connect.
application.register("variant-gallery", VariantGalleryController)
application.register("variant-picker", VariantPickerController)

lazyLoadControllersFrom("controllers", application)
